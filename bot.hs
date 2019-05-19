{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}

import Control.Monad
import Network.HTTP
import Network.HTTP.Conduit
import Network.HTTP.Types.Header
import GHC.Generics
import Data.Maybe
import Data.Aeson
import Data.Aeson.Types
import Data.ByteString.Lazy.Internal
import Prelude hiding (id)
import Control.Concurrent
import Control.Concurrent.STM
import Control.Exception (finally)
import Control.Monad (when)
import Data.Monoid ((<>))
import Data.Char (toLower)
import System.IO
import System.Environment
import qualified Data.Text as T
import qualified Data.Text.IO as TIO

import Discord


-- For Parsing

data VideoId = VideoId {
    videoId :: String }
    deriving (Generic, Show)

data IdContainer = IdContainer {
    id :: VideoId }
    deriving (Generic, Show)

data ItemContainer = ItemContainer {
    items :: [IdContainer] }
    deriving (Generic, Show)

instance FromJSON VideoId
instance FromJSON IdContainer
instance FromJSON ItemContainer


-- Query

queryYoutube :: IO (Maybe String)
queryYoutube = do
  initReq <- parseRequest "https://www.googleapis.com/youtube/v3/search"
  let request = setQueryString [("part", Just "snippet"), ("channelId", Just "UC6cqazSR6CnVMClY0bJI0Lg"), ("maxResults", Just "1"), ("order", Just "date"), ("type", Just "video"), ("key", Just "<youtube api key>")] initReq -- OH SHIT SO LONG STRING, I want to add some text to make it even more longer, hehehehehheheheh
  manager <- newManager tlsManagerSettings
  res <- httpLbs request manager
  let decoded = liftM items . decode . responseBody $ res
  return $ case decoded of
    Nothing -> Just "parse error" -- i think it's funny
    Just items -> extractVideoId (Just items)

extractVideoId :: Maybe [IdContainer] -> Maybe String
extractVideoId Nothing = Nothing
extractVideoId (Just [IdContainer (VideoId vidId)]) = Just vidId



-- Bot Start

connectBot :: IO ()
connectBot = do
  dis <- loginRestGateway (Auth "<Discord bot token>")
  resp <- restCall dis (CreateMessage <Discord channelid> "All systems online, powered by haskell")
  finally (notificationRun dis)
          (stopDiscord dis)



-- Command Reaction Mode

commandReaction :: (RestChan, Gateway, z) -> IO ()
commandReaction dis = do
  e <- nextEvent dis
  case e of
    Left er -> putStrLn $ "Event error: " <> show er
    Right (MessageCreate m) -> do
      when ((messageText m) == "!getNewest") $ do
        timer1 <- newTimer (2 * 1000000)
        waitTimer timer1
        putStrLn "timer expired"
        vidId <- queryYoutube
        resp <- restCall dis (CreateMessage (messageChannel m) $ T.append "https://www.youtube.com/watch?v=" (T.pack (fromJust vidId)))
        putStrLn $ show resp
        putStrLn ""
      commandReaction dis
    _ -> commandReaction dis



-- Notification Mode

notificationRun :: (RestChan, Gateway, z) -> IO ()
notificationRun dis = do
  timer1 <- newTimer (3600 * 1000000)
  waitTimer timer1
  vidId <- queryYoutube
  sourceFile <- openFile "lastsent.txt" ReadMode
  lastUrl <- hGetLine sourceFile
  hClose sourceFile
  destinationFile <- openFile "lastsent.txt" WriteMode
  if (lastUrl == "") || lastUrl /= (fromJust vidId)
    then restCall dis (CreateMessage <Discord channelid> $ T.append "https://www.youtube.com/watch?v=" (T.pack (fromJust vidId)))
    else restCall dis (CreateMessage <Discord channelid> $ "")
  hPutStr destinationFile (fromJust vidId)
  hClose destinationFile
  notificationRun dis





-- Timer (copyied from "https://lotz84.github.io/haskellbyexample/ex/timers")

data State = Start | Stop
type Timer = (TVar State, TMVar ())

waitTimer :: Timer -> IO ()
waitTimer (_, timer) = atomically $ readTMVar timer

stopTimer :: Timer -> IO ()
stopTimer (state, _) = atomically $ writeTVar state Stop

newTimer :: Int -> IO Timer
newTimer n = do
    state <- atomically $ newTVar Start
    timer <- atomically $ newEmptyTMVar
    forkIO $ do
        threadDelay n
        atomically $ do
            runState <- readTVar state
            case runState of
                Start -> putTMVar timer ()
                Stop  -> return ()
    return (state, timer)

--
