module Main where

import           System.Environment   (getArgs)
import           Lib

main :: IO ()
main = do
  (brokerAddress:topic:iterStr:_) <- getArgs
  let iterations = read iterStr :: Integer
  executeProducer brokerAddress topic iterations

