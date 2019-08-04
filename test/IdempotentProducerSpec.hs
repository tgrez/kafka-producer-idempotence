{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE DuplicateRecordFields #-}

module IdempotentProducerSpec where

import System.Environment
import System.FilePath.Posix
import System.Posix.Types
import System.Hatrace

import Control.Monad.Reader
import Control.Concurrent.STM.TVar
import Control.Concurrent.STM

import GHC.IO.Exception

import Data.Conduit
import qualified Data.Conduit.List as CL
import Test.Hspec

import Lib

spec :: Spec
spec = do
  describe "kafka idempotent producer" $ do
    it "sends messages which can be intercepted" $ do
      execPath <- takeDirectory <$> getExecutablePath
      let cmd = execPath </> "../idempotent-producer-exe/idempotent-producer-exe"
      argv <- procToArgv cmd []
      counter <- newTVarIO (2 :: Int)
      (exitCode, events) <- flip runReaderT counter $
        sourceTraceForkExecvFullPathWithSink argv $
          syscallExitDetailsOnlyConduit .|
          objectFileWriteFilterConduit2 .|
          CL.consume
      exitCode `shouldBe` ExitSuccess
--      mapM_ print events
      length events  `shouldSatisfy` (> 0)

type SyscallEvent = (CPid, Either (Syscall, ERRNO) DetailedSyscallExit)

objectFileWriteFilterConduit2 :: (MonadIO m, MonadReader (TVar Int) m) => ConduitT SyscallEvent SyscallEvent m ()
objectFileWriteFilterConduit2 = awaitForever $ \(pid, exitOrErrno) -> do
        counterTVar <- ask
        counter <- liftIO $ atomically $ do
          modifyTVar' counterTVar (+1)
          readTVar counterTVar
        yield (pid, exitOrErrno)
        case exitOrErrno of
          Left{} -> return () -- ignore erroneous syscalls
          Right exit -> case exit of
            DetailedSyscallExit_open
              SyscallExitDetails_open
                { enterDetail = SyscallEnterDetails_open { pathnameBS } } -> do
                   liftIO $ print $ show counter <> " : " <> show pathnameBS
            _ -> return ()
