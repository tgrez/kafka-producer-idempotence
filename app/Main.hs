module Main where

import           System.Environment   (getArgs)
import           Lib

main :: IO ()
main = do
  (brokerAddress:topic:iterStr:enableIdempotenceStr:_) <- getArgs
  let iterations = read iterStr :: Integer
      enableIdempotence = read enableIdempotenceStr :: Bool
  executeProducer brokerAddress topic iterations enableIdempotence

