---
date: 2013-08-17 15:00:00
description: A comparison of Kal (a new JavaScript-transpiled language) to monadic code in Haskell.
layout: post
tags: haskell monads
title: "Kal Me Maybe"
---

A post just went up on [HackerNews recently][kal-hn] announcing a new
JavaScript-transpiled language named Kal. In the author's own words, the
main design goals of Kal are:

1. Eliminate the yucky parts of JavaScript, but keep the good stuff including the compatibility, and the great server and client runtime support.
2. Make code as readable as possible and make writing code straightforward. Eliminate the urge (and the need) to be terse and complicated.
3. Provide an alternative to callbacks (which look weird) and promises (which are weird) while providing excellent, easy-to-use asynchronous support.

Looking over Kal, I thought it was pretty cool. The use-case of making
asynchronous control flow easier to reason about sounds great, even if I
don't do that much day-to-day async JavaScript programming. As I was
looking at the following example in particular...

{% highlight python %}
task getUserFriends(userName)
  wait for user from db.users.findOne {name:userName}
  wait for friends from db.friends.find {userId:user.id}
  if user.type is 'power user'
    for parallel friend in friends
      wait for friendsOfFriend from db.friends.find friend
      for newFriend in friendsOfFriend
        friends.push newFriend unless newFriend in friends
  return friends
{% endhighlight %}

...it struck me how much this looked like monadic code. I spent a few
minutes throwing together a pseudo-ish Haskell implementation to see how
similar they looked, and posted a [comment to HN][hn-comment] containing the
following code:

{% highlight haskell %}
getUserFriends userName = do
  user <- findUser userName
  friends <- findFriends user
  if (User.type user) == "power user"
    then friends ++ parMap rdeepseq $ (getSecondNodes friends) friends
    else friends
  
getSecondNodes firstNodes friend = do
  secondNodes <- findFriends friend
  diff firstNodes secondNodes
{% endhighlight %}

At first, I was satisfied with the conclusion that Kal offers monad-like
structures as baked-in language features, but that this sort of
control-flow is just as easy to accomplish in a sufficiently powerful
language. However, as Sean Bean knows...

<p class="image-container">
  <img src="http://i.imgur.com/Dg3ForQ.jpg" alt="Aragorn cautioning: 'One does not simply write a correct Haskell program" />
</p>

In truth, this quick Haskell program doesn't even compile. So, I sat down to actually write a compilable
implementation. Swagging the data-gathering functions like so...

{% highlight haskell %}
data User = User { classification :: String } deriving (Eq,Show)

findUser :: String -> Maybe User
findUser userName = Nothing

findFriends :: User -> Maybe [User]
findFriends user = Nothing
{% endhighlight %}

...I ended up with the following _real_ implementation.

{% highlight haskell %}
getUserFriends :: String -> Maybe [User]
getUserFriends userName = do
  user <- findUser userName
  friends <- findFriends user
  if (classification user) == "power user"
    then Just (nub $ friends ++ concat (parMap rseq (getSecondNodes friends) friends))
    else Just friends

getSecondNodes :: [User] -> User -> [User]
getSecondNodes firstNodes friend = fromMaybe [] $ getSecondNodes' firstNodes friend

getSecondNodes' :: [User] -> User -> Maybe [User]
getSecondNodes' firstNodes friend = do
  secondNodes <- findFriends friend
  Just $ firstNodes \\ secondNodes
{% endhighlight %}

Woof. That's a little worse, isn't it? This version is also sub-optimal
compared to the Kal version, since there is an additional step ensuring
uniqueness at the very end of combining the second-hop nodes. I'd also
argue that it's much less clear what's happening. Admittedly I am hardly
an experienced Haskeller, so there is probably a cleaner version; if so,
I'd love to see it! Check out the full source on [GitHub][kal-hs-src].

Although my initial reaction to Kal may have been "I can just
do this with monads", maybe there is some value in dedicating specific
syntax to this problem. Besides, as we all know...

<p class="image-container">
  <img src="http://i.qkme.me/3tt5gu.jpg" alt="Biggie Smalls, stating: Monads mo' problems" />
</p>

Preach it Biggie.

[kal-hn]: https://news.ycombinator.com/item?id=6227517
[kal-hs-src]: https://github.com/rybosome/rybosome.github.io/blob/master/src/2013-08-17-kal-me-maybe/kal.hs
[hn-comment]: https://news.ycombinator.com/item?id=6227820
