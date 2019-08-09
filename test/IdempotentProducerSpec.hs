{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

module IdempotentProducerSpec where

import System.Environment
import System.FilePath.Posix
import System.Posix.Types
import System.Hatrace

import Control.Monad.Reader
import Control.Concurrent.STM.TVar
import Control.Concurrent.STM
import Control.Exception


import GHC.IO.Exception

import Data.Monoid ((<>))
import qualified Data.Text as T
import qualified Data.ByteString as B
import Data.Conduit
import qualified Data.Conduit.List as CL
import Test.Hspec

import Kafka.Broker
import Kafka.Consumer

brokerAddress :: String
brokerAddress = "localhost:9092"
kafkaTopic :: String
kafkaTopic = "haskell-temp-test"
messageCount :: Int
messageCount = 5

spec :: Spec
spec = around_ withKafka $ do
  describe "kafka producer" $ do
    it "sends duplicate messages on timeouts" $ do
      execPath <- takeDirectory <$> getExecutablePath
      let cmd = execPath </> "../idempotent-producer-exe/idempotent-producer-exe"
      argv <- procToArgv cmd [brokerAddress, kafkaTopic, show messageCount]
      counter <- newTVarIO (0 :: Int)
      (exitCode, events) <- flip runReaderT counter $
        sourceTraceForkExecvFullPathWithSink argv $
          syscallExitDetailsOnlyConduit .|
          changeSendmsgSyscallResult .|
          CL.consume
      msgs <- consumeMessages
      print msgs
      msgs `shouldSatisfy` (\case
                               Right messages -> length messages == 7
                               Left _ -> False
                           )
      exitCode `shouldBe` ExitSuccess
      length events  `shouldSatisfy` (> 0)

withKafka :: IO () -> IO ()
withKafka action =
  bracket startKafka stopKafka (const action)
  where
    startKafka = do
      zkContainerId <- runZookeeperContainer
      putStrLn "    zookeeper started"
      kafkaContainerId <- runKafkaContainer
      putStrLn "    kafka broker started"
      pure (zkContainerId, kafkaContainerId)
    stopKafka (zkContainerId, kafkaContainerId) = do
      destroyContainer kafkaContainerId
      putStrLn "    kafka broker stopped"
      destroyContainer zkContainerId
      putStrLn "    zookeeper stopped"

consumerProps :: ConsumerProperties
consumerProps = brokersList [BrokerAddress $ T.pack brokerAddress]
             <> groupId (ConsumerGroupId "testConsumerGroup")
             <> logLevel KafkaLogAlert

consumerSub :: Subscription
consumerSub = topics [TopicName $ T.pack kafkaTopic]
           <> offsetReset Earliest

consumeMessages :: IO (Either KafkaError [Maybe B.ByteString])
consumeMessages = do
    bracket mkConsumer clConsumer runHandler
    where
      mkConsumer = newConsumer consumerProps consumerSub
      clConsumer (Left err) = pure (Left err)
      clConsumer (Right kc) = (maybe (Right ()) Left) <$> closeConsumer kc
      runHandler (Left err) = pure (Left err)
      runHandler (Right kc) = Right <$> processMessages kc

processMessages :: KafkaConsumer -> IO [Maybe B.ByteString]
processMessages kc = processInternal kc (0 :: Int) []
  where
    processInternal kafkaConsumer continuousErrorsNum messages =
      if continuousErrorsNum > 15
        then pure messages
        else do
          pollMessage kafkaConsumer (Timeout 1000) >>= \case
            Left _ ->
              processInternal kafkaConsumer (continuousErrorsNum + 1) messages
            Right (ConsumerRecord{crValue}) ->
              processInternal kafkaConsumer 0 (crValue:messages)

        

type SyscallEvent = (CPid, Either (Syscall, ERRNO) DetailedSyscallExit)

changeSendmsgSyscallResult :: (MonadIO m, MonadReader (TVar Int) m) => ConduitT SyscallEvent SyscallEvent m ()
changeSendmsgSyscallResult = awaitForever $ \(pid, exitOrErrno) -> do
        yield (pid, exitOrErrno)
        case exitOrErrno of
          Left{} -> pure () -- ignore erroneous syscalls
          Right exit -> case exit of
            DetailedSyscallExit_sendmsg
              SyscallExitDetails_sendmsg
                { bytesSent } -> do
                  when (("msg2" `B.isInfixOf` bytesSent)) $ do
                    counterTVar <- ask
                    counter <- liftIO $ atomically $ do
                      modifyTVar' counterTVar (+1)
                      readTVar counterTVar
                    when (counter < 3) $
                      liftIO $ setExitedSyscallResult pid (-110)
            _ -> pure ()
