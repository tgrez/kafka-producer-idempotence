module Main where

import           Lib
import           System.Environment (getArgs)

main :: IO ()
main = do
  (brokerAddress:topic:iterStr:enableIdempotenceStr:_) <- getArgs
  let iterations = read iterStr :: Integer
      enableIdempotence = read enableIdempotenceStr :: Bool
  executeProducer brokerAddress topic iterations enableIdempotence

