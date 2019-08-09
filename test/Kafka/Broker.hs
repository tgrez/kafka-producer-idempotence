{-# LANGUAGE OverloadedStrings #-}
module Kafka.Broker ( runKafkaContainer
                    , runZookeeperContainer
                    , destroyContainer) where

import Control.Monad.Catch
import Control.Monad.IO.Unlift
import Data.Text
import Docker.Client

dockerHttpHandler :: (MonadUnliftIO m, MonadIO m, MonadMask m) => m (HttpHandler m)
dockerHttpHandler = unixHttpHandler "/var/run/docker.sock"

destroyContainer :: ContainerID -> IO ()
destroyContainer containerId' = do
  h <- dockerHttpHandler
  runDockerT (defaultClientOpts, h) $ do
    stopResult <- stopContainer DefaultTimeout containerId'
    case stopResult of
      Left err -> error $ show err
      Right () -> pure ()
    deleteResult <- deleteContainer defaultContainerDeleteOpts containerId'
    case deleteResult of
      Left err -> error $ show err
      Right () -> pure ()

runZookeeperContainer :: IO ContainerID
runZookeeperContainer = do
  h <- dockerHttpHandler
  runDockerT (defaultClientOpts, h) $ do
    let pb = PortBinding 2181 TCP [HostPort "0.0.0.0" 2181]
        zkEnvVars = [ EnvVar "ZOO_MY_ID" "1"
                    , EnvVar "ZOO_PORT" "2181"
                    , EnvVar "ZOO_SERVERS" "server.1=zoo1:2888:3888"
                    ]
    let createOpts = setHostname "zoo1"
                     $ addEnvVars zkEnvVars
                     $ addPortBinding pb
                     $ defaultCreateOpts "zookeeper:3.4.9"
    cid <- createContainer createOpts $ Just "zoo1"
    case cid of
      Left err -> error $ show err
      Right i -> do
        result <- startContainer defaultStartOpts i
        case result of
          Left err -> error $ show err
          Right _ -> return i

runKafkaContainer :: IO ContainerID
runKafkaContainer = do
    h <- dockerHttpHandler
    runDockerT (defaultClientOpts, h) $ do
      let pb = PortBinding 9092 TCP [HostPort "0.0.0.0" 9092]
          kafkaEnv = [ EnvVar "KAFKA_ADVERTISED_LISTENERS" "LISTENER_DOCKER_INTERNAL://kafka1:19092,LISTENER_DOCKER_EXTERNAL://127.0.0.1:9092"
                     , EnvVar "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP" "LISTENER_DOCKER_INTERNAL:PLAINTEXT,LISTENER_DOCKER_EXTERNAL:PLAINTEXT"
                     , EnvVar "KAFKA_INTER_BROKER_LISTENER_NAME" "LISTENER_DOCKER_INTERNAL"
                     , EnvVar "KAFKA_ZOOKEEPER_CONNECT" "zoo1:2181"
                     , EnvVar "KAFKA_BROKER_ID" "1"
                     , EnvVar "KAFKA_LOG4J_LOGGERS" "kafka.controller=INFO,kafka.producer.async.DefaultEventHandler=INFO,state.change.logger=INFO"
                     , EnvVar "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR" "1"
                     ]
      let createOpts = setHostname "kafka1"
                       $ addLink (Link "zoo1" (Just "zoo1"))
                       $ addEnvVars kafkaEnv
                       $ addPortBinding pb
                       $ defaultCreateOpts "confluentinc/cp-kafka:5.2.1"
      cid <- createContainer createOpts $ Just "kafka1"
      case cid of
        Left err -> error $ show err
        Right i -> do
          result <- startContainer defaultStartOpts i
          case result of
            Left err -> error $ show err
            Right _ -> return i

setHostname :: Text -> CreateOpts -> CreateOpts
setHostname hostname' c = c { containerConfig = cc { hostname = Just hostname' } }
  where
    cc = containerConfig c

addEnvVars :: [EnvVar] -> CreateOpts -> CreateOpts
addEnvVars newVars c = c { containerConfig = cc { env = newVars ++ vars } }
  where
    cc = containerConfig c
    vars = env cc
