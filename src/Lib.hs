{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

module Lib
    ( executeProducer
    ) where

import           Control.Exception    (bracket)
import           Control.Monad        (forM_)
import           Data.ByteString      (ByteString)
import qualified Data.ByteString.UTF8 as BSU
import           Data.Map.Strict      as M
import qualified Data.Text            as T
import           Kafka.Producer

producerProps :: String -> Bool -> ProducerProperties
producerProps brokerAddress enableIdempotence = brokersList [BrokerAddress $ T.pack brokerAddress]
             <> (extraProps $ M.fromList [ ("batch.num.messages", "1")
                                         , ("max.in.flight", "1") -- so only 1 msg is resend
                                         , ("enable.idempotence", T.toLower $ T.pack $ show enableIdempotence)
                                         ]
                )
             <> logLevel KafkaLogErr

executeProducer :: String -> String -> Integer -> Bool -> IO ()
executeProducer brokerAddress topic iterations enableIdempotence = do
    bracket mkProducer clProducer runHandler >>= \case
      Right () -> putStrLn "messages were sent to broker"
      Left err -> putStrLn $ show err
    where
      mkProducer = newProducer $ producerProps brokerAddress enableIdempotence
      clProducer (Left _)     = return ()
      clProducer (Right prod) = closeProducer prod
      runHandler (Left err)   = return $ Left err
      runHandler (Right prod) = sendMessages prod topic iterations

sendMessages :: KafkaProducer -> String -> Integer -> IO (Either KafkaError ())
sendMessages prod topic iterations = do
  forM_ [1..iterations] $ produceMessage prod . mkMsg
  pure $ Right ()
  where
    msgValue n = Just $ "msg" <> BSU.fromString (show n)
    mkMsg = mkMessage topic Nothing . msgValue

mkMessage :: String -> Maybe ByteString -> Maybe ByteString -> ProducerRecord
mkMessage t k v = ProducerRecord
                  { prTopic = TopicName $ T.pack t
                  , prPartition = UnassignedPartition
                  , prKey = k
                  , prValue = v
                  }
