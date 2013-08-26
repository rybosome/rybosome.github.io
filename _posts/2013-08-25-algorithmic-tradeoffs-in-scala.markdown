---
date: 2013-08-25 15:30:00
description: Discusses tradeoffs in memory usage and binary tree design, examples in Scala.
layout: post
tags: scala fp
title: "Algorithmic Tradeoffs In Scala"
---

As I'm prone to doing, several weeks ago I [hijacked a
discussion][hn-hijack] on
HackerNews covering Go to steer the discussion towards Scala. The
context was around Go's switch statement, which is somewhat more powerful than
that found in C et al. I couldn't resist the opportunity to point out
how awesome pattern matching in Scala is, noting that it is like "switch
on steroids" according to [scala-lang][scala-lang]. The toy example I came up with centered around the problem
of getting all leaf node values from a binary tree.

### First take

{% highlight scala %}
sealed abstract class Node[A]
case class Fork[A](value: A, left: Node[A], right: Node[A]) extends Node[A]
case class Leaf[A](value: A) extends Node[A]

object Src {

  def getLeafNodeValues[A](node: Node[A]): List[A] = node match {
    case Fork(value, left, right) => getLeafNodeValues(left) ++ getLeafNodeValues(right)
    case Leaf(value) => List(value)
  }

}

{% endhighlight %}

If you're at all familiar with pattern matching, this is a pretty basic
example. A node in a tree must be either a fork or a leaf, so getting
leaf nodes is a simple task once we've determined what type of node we
are dealing with. Pattern matching provides syntactic sugar around
determining the type of a node and extracting the values from it into
local variables. This is actually quite similar to an
example in Twitter's [Scala School][scala-school], where they note that the
implementation is "obviously correct".

Ok, neat; this is idiomatic functional code, but this is also
exactly the sort of algorithm you will see demonstrating the dangers of recursion. On extremely large
trees this will cause stack overflow, since we may recurse a very great
number of times while exploring the tree.

<p class="image-container">
  <img src="https://github-camo.global.ssl.fastly.net/5a0fbd97b20bd684ca178b122c6b700a53e85587/687474703a2f2f63646e2e6d656d6567656e657261746f722e6e65742f696e7374616e6365732f353030782f33343436313433342e6a7067" alt="The most interesting man in the world proving that nobody is above stack overflow" />
</p>

### Tail call optimization

As is true for many other recursive data structures, recursion is a natural way
to process a binary tree. It's certainly possible to do so iteratively,
but some algorithms may be awkward or unidiomatic.
Luckily, there's a way to use infinite recursion without blowing
the stack; [tail call
optimization][tail-call-optimization]. In plain English, this means that
the return value of a function consists solely of either a value, or the
return value of another function call. If we make a recursive call that
does not require preserving any state from the current function call,
then theoretically we could reuse the stack frame allocated to this
function call. A simple example of this
can be seen in the factorial function:

{% highlight scala %}
// Not tail callable
def factorial(n: Int): Int = n match {
  case n if n <= 0 => 1
  case _ => n * factorial(n - 1)
}

// Tail callable
@tailrec
def betterFactorial(n: Int, acc: Int = 1): Int = n match {
  case n if n <= 0 => acc
  case _ => betterFactorial(n - 1, acc * n)
}
{% endhighlight %}

Writing a function that can be tail called essentially just requires passing the
state which you would have preserved in local variables into the
function. The JVM doesn't implement true tail call optimization, but the
Scala compiler will attempt to optimize tail-recursive function calls
into efficient loops. By annotating the function with [@tailrec][scala-tailrec],
we are asking the compiler to warn us if it is unable to do so.

Taking another swag at our leaf value collection function,
we could write it like so:

{% highlight scala %}
import scala.annotations.tailrec

sealed abstract class Node[A]
case class Fork[A](value: A, left: Node[A], right: Node[A]) extends Node[A]
case class Leaf[A](value: A) extends Node[A]

object Src {

  def getLeafNodeValues(node: Node[A]): List[A] = getValuesFromList(List.empty[A], List(node))

  @tailrec
  def getValuesFromList(accValues: List[A], nodeList: List[Node[A]]): List[A] = nodeList match {
    case head :: tail => head match {
      case Fork(left, right) => getValuesFromList(accValues, left :: right :: tail)
      case Leaf(value) => getValuesFromList(value :: accValues, tail)
    }
    case _ => accValues
  }

}
{% endhighlight %}

While this code will not blow the stack, it's less obvious what
is going on. An additional downside to this approach is that we are essentially
duplicating the binary tree as a
flattened list in memory, so our memory usage is roughly going to be
linear with respect to the depth of the tree.

### Here's where things get fuzzy

I began wondering if it was possible to get the best of both worlds: is
there a way to collect all of the leaf nodes from a binary tree (as
we've defined it here) in a tail call optimized manner while only using O(1)
additional storage? Note: there is the unavoidable memory cost of gathering
the leaf nodes, which is O(2<sup>d</sup>) in a perfectly balanced tree, with d
being the depth.

The first thing that leapt to mind was an iterator. By creating a data
structure that can traverse this tree on-demand, we could gather up the
leaf nodes. Great. The problem is; how? Here was my line of reasoning:

1. To implement an O(1) iterator, there must be a way to determine from
   a single node which the next node to traverse is. We need a _getNext_ function.
2. To implement this _getNext_ function, we need some way of determining
   from a node which paths have already been traversed.
3. One way of doing that is by preserving the list of traversed nodes,
   but that conflicts with the goal of using O(1) space.
4. Another option is to use mutable state (modify the node indicating
   that it's been traversed somehow), but I'd prefer not to, since we
   only have two yucky choices from this:
   1. Make the leaf gathering function be non-referentially transparent,
      i.e. gathering the leaves permanently modifies the state of the
      tree.
   2. Walk the tree a second time to "reset" it.

<p class="image-container">
  <img src="http://i.imgur.com/1EC0hmV.jpg" alt="Alec Baldwin scoffing
at the idea of a lack of referential transparency" />
</p>

The root of the problem is that we have to have a way to get from a
child to its parent, and the only way (based on the current
implementation) is to preserve that state explicitly.

### Hard questions, hard answers

I took to [StackOverflow][stack-overflow-thread] to see if the wise folk there had some
insights. We essentially ended up at a "[short answer: 'Yes' with an 'If,' long answer: 'No' -- with a 'But.'][simpsons-quote]".

Short answer: "yes, you can implement this best-of-both-worlds approach IF
you have a link to the parent or modify the tree".

Long answer: "No, you cannot implement
the algorithm as it stands, [BUT you can get relatively efficient memory
usage][stack-overflow-long-answer]".

I'll admit to not understanding that last one...as is evident from my [previous post][previous-post], I am not exactly a
Haskell wizard.

### Taking the easy way out

If we modify the implementation such that every node has an optional
link back to its parent (optional since the root won't have one, and
null isn't idiomatic), we can mixin [Traversable][scala-traversable]
with Node, with the implementation of _getNext_ provided seperately by each sub-type.
The implementation could look like this:

{% highlight scala %}
sealed abstract class Node[A] extends Traversable[Node[A]] {
  def parent: Option[Node[A]]
  def value: A

  def getNext[A](prev: Node[A]): Option[Node[A]]

  def foreach[B](f: Node[A] => B): Unit = applyForeach(Some(this), f)

  def applyForeach[B](n: Option[Node[A]], f: Node[A] => B): Unit = n match {
    case Some(n) =>
      f(n)
      applyForeach(getNext(n), f)
    case None => Unit
  }
}

case class Fork[A](value: A, left: Node[A], right: Node[A], parent: Option[Node[A]]) extends Node[A] {
  def getNext[A](prev: Node[A]): Option[Node[A]] = {
    if (prev == left) Some(right)
    else if (prev == right) parent
    else Some(left)
  }
}

case class Leaf[A](value: A, parent: Option[Node[A]]) extends Node[A] {
  def getNext[A](prev: Node[A]): Option[Node[A]] = parent
}

object Src {

  def getLeafNodeValues[A](node: Node[A]): List[A] = node.filter {
    case _: Leaf[A] => true
    case _ => false
  }.map { _.value }.toList


}
{% endhighlight %}

One cool consequence of implementing _Traversable_ is that this enables us to implement the
leaf-node-value-gathering function via combinators rather than recursion. The actual grunt work of efficiently traversing
the tree is always going to be the same, so this allows us to separate
traversal from whatever else we want to do with the tree. Neat. =)

### Conclusion

By modifying our implementation of binary trees, we were able to achieve
a best-case scenario as far as traversal efficiency is concerned. In
addition, we were able to restrict the harder-to-understand pieces of
code into a single, abstractable unit. Without doing so, there was
always going to be an inefficiency present, due to the nature of this
problem.

<p class="image-container">
  <img src="http://i.qkme.me/3vlk5u.jpg" alt="Craig from South Park
indicating how happy he would be writing Scala all day." />
</p>

...and Scala is awesome.

[hn-hijack]: https://news.ycombinator.com/item?id=6136316
[previous-post]: http://ryboso.me/kal-me-maybe.html
[scala-lang]: http://www.scala-lang.org/
[scala-school]: http://twitter.github.io/effectivescala/#Functional%20programming-Case%20classes%20as%20algebraic%20data%20types
[scala-tailrec]: http://www.scala-lang.org/api/current/index.html#scala.annotation.tailrec
[scala-traversable]: http://www.scala-lang.org/api/current/index.html#scala.collection.Traversable
[simpsons-quote]: http://imgur.com/r/TheSimpsons/gWcFj
[stack-overflow-long-answer]: http://stackoverflow.com/a/18363997/404917
[stack-overflow-thread]: http://stackoverflow.com/questions/18345734/is-it-possible-to-lazily-traverse-a-recursive-data-structure-with-o1-memory-us
[tail-call-optimization]: http://en.wikipedia.org/wiki/Tail_call
