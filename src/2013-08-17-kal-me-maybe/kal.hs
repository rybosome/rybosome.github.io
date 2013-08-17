module Rybosome where

import Control.Parallel.Strategies
import Data.List
import Data.Maybe

data User = User { classification :: String } deriving (Eq,Show)

findUser :: String -> Maybe User
findUser userName = Nothing

findFriends :: User -> Maybe [User]
findFriends user = Nothing

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
