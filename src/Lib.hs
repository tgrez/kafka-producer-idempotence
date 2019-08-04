{-# LANGUAGE OverloadedStrings #-}

module Lib
    ( someFunc
    ) where

import           System.Environment   (getArgs)
import           Control.Exception    (bracket)
import           Control.Concurrent
import           Control.Monad        (forM_, replicateM, when)
import           Data.ByteString      (ByteString)
import qualified Data.ByteString.UTF8 as BSU
import           Kafka.Producer
import qualified Data.Text            as T

someFunc :: IO ()
someFunc = do
--  (brokerAddress:topic:iterStr:_) <- getArgs
  let brokerAddress = "localhost:9092"
      topic = "haskell-temp-test"
      iterStr = "5"
  let iterations = read iterStr :: Integer
  executeProducer brokerAddress topic iterations 1

-- Global producer properties
producerProps :: String -> ProducerProperties
producerProps brokerAddress = brokersList [BrokerAddress $ T.pack brokerAddress]
             <> logLevel KafkaLogDebug

-- Run an example
executeProducer :: String -> String -> Integer -> Integer -> IO ()
executeProducer brokerAddress topic iterations currIter  = do
    bracket mkProducer clProducer runHandler >>= print
--    threadDelay 1000000
    when (currIter < iterations) $ executeProducer brokerAddress topic iterations (currIter + 1)
    where
      mkProducer = newProducer $ producerProps brokerAddress
      clProducer (Left _)     = return ()
      clProducer (Right prod) = closeProducer prod
      runHandler (Left err)   = return $ Left err
      runHandler (Right prod) = sendMessages prod topic currIter

sendMessages :: KafkaProducer -> String -> Integer -> IO (Either KafkaError ())
sendMessages prod topic currIter = do
  err1 <- produceMessage prod (mkMessage topic Nothing (Just $ "msg" <> BSU.fromString (show currIter)) )
  forM_ err1 print

  return $ Right ()

mkMessage :: String -> Maybe ByteString -> Maybe ByteString -> ProducerRecord
mkMessage t k v = ProducerRecord
                  { prTopic = TopicName $ T.pack t
                  , prPartition = UnassignedPartition
                  , prKey = k
                  , prValue = v
                  }
