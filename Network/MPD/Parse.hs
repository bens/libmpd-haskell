module Network.MPD.Parse where

import Control.Monad.Error
import Network.MPD.Utils
import Network.MPD.Core (MPD, MPDError(Unexpected))

type Seconds = Integer

-- | Represents a song's playlist index.
data PLIndex = Pos Integer -- ^ A playlist position index (starting from 0)
             | ID Integer  -- ^ A playlist ID number that more robustly
                           --   identifies a song.
    deriving (Show, Eq)

-- | Represents the different playback states.
data State = Playing
           | Stopped
           | Paused
    deriving (Show, Eq)

-- | Represents the result of running 'count'.
data Count =
    Count { cSongs    :: Integer -- ^ Number of songs matching the query
          , cPlaytime :: Seconds -- ^ Total play time of matching songs
          }
    deriving (Eq, Show)

parseCount :: [String] -> Either String Count
parseCount = foldM f empty . toAssoc
        where f a ("songs", x)    = parse parseNum
                                    (\x' -> a { cSongs = x'}) x
              f a ("playtime", x) = parse parseNum
                                    (\x' -> a { cPlaytime = x' }) x
              f _ x               = Left $ show x
              empty = Count { cSongs = 0, cPlaytime = 0 }

-- | Represents an output device.
data Device =
    Device { dOutputID      :: Int    -- ^ Output's ID number
           , dOutputName    :: String -- ^ Output's name as defined in the MPD
                                      --   configuration file
           , dOutputEnabled :: Bool }
    deriving (Eq, Show)

-- | Retrieve information for all output devices.
parseOutputs :: [String] -> Either String [Device]
parseOutputs = mapM (foldM f empty) . splitGroups [("outputid",id)] . toAssoc
    where f a ("outputid", x)      = parse parseNum (\x' -> a { dOutputID = x' }) x
          f a ("outputname", x)    = return a { dOutputName = x }
          f a ("outputenabled", x) = parse parseBool
                                     (\x' -> a { dOutputEnabled = x'}) x
          f _ x                    = fail $ show x
          empty = Device 0 "" False

-- | Container for database statistics.
data Stats =
    Stats { stsArtists    :: Integer -- ^ Number of artists.
          , stsAlbums     :: Integer -- ^ Number of albums.
          , stsSongs      :: Integer -- ^ Number of songs.
          , stsUptime     :: Seconds -- ^ Daemon uptime in seconds.
          , stsPlaytime   :: Seconds -- ^ Total playing time.
          , stsDbPlaytime :: Seconds -- ^ Total play time of all the songs in
                                     --   the database.
          , stsDbUpdate   :: Integer -- ^ Last database update in UNIX time.
          }
    deriving (Eq, Show)

parseStats :: [String] -> Either String Stats
parseStats = foldM f defaultStats . toAssoc
    where
        f a ("artists", x)  = parse parseNum (\x' -> a { stsArtists  = x' }) x
        f a ("albums", x)   = parse parseNum (\x' -> a { stsAlbums   = x' }) x
        f a ("songs", x)    = parse parseNum (\x' -> a { stsSongs    = x' }) x
        f a ("uptime", x)   = parse parseNum (\x' -> a { stsUptime   = x' }) x
        f a ("playtime", x) = parse parseNum (\x' -> a { stsPlaytime = x' }) x
        f a ("db_playtime", x) = parse parseNum
                                 (\x' -> a { stsDbPlaytime = x' }) x
        f a ("db_update", x) = parse parseNum (\x' -> a { stsDbUpdate = x' }) x
        f _ x = fail $ show x
        defaultStats =
            Stats { stsArtists = 0, stsAlbums = 0, stsSongs = 0, stsUptime = 0
                  , stsPlaytime = 0, stsDbPlaytime = 0, stsDbUpdate = 0 }

-- | Container for MPD status.
data Status =
    Status { stState :: State
             -- | A percentage (0-100)
           , stVolume          :: Int
           , stRepeat          :: Bool
           , stRandom          :: Bool
             -- | A value that is incremented by the server every time the
             --   playlist changes.
           , stPlaylistVersion :: Integer
             -- | The number of items in the current playlist.
           , stPlaylistLength  :: Integer
             -- | Current song's position in the playlist.
           , stSongPos         :: Maybe PLIndex
             -- | Current song's playlist ID.
           , stSongID          :: Maybe PLIndex
             -- | Time elapsed\/total time.
           , stTime            :: (Seconds, Seconds)
             -- | Bitrate (in kilobytes per second) of playing song (if any).
           , stBitrate         :: Int
             -- | Crossfade time.
           , stXFadeWidth      :: Seconds
             -- | Samplerate\/bits\/channels for the chosen output device
             --   (see mpd.conf).
           , stAudio           :: (Int, Int, Int)
             -- | Job ID of currently running update (if any).
           , stUpdatingDb      :: Integer
             -- | Last error message (if any).
           , stError           :: String }
    deriving Show

parseStatus :: [String] -> Either String Status
parseStatus = foldM f empty . toAssoc
    where f a ("state", x)          = parse state (\x' -> a { stState = x'}) x
          f a ("volume", x)         = parse parseNum (\x' -> a { stVolume = x'}) x
          f a ("repeat", x)         = parse parseBool
                                      (\x' -> a { stRepeat = x' }) x
          f a ("random", x)         = parse parseBool
                                      (\x' -> a { stRandom = x' }) x
          f a ("playlist", x)       = parse parseNum
                                      (\x' -> a { stPlaylistVersion = x'}) x
          f a ("playlistlength", x) = parse parseNum
                                      (\x' -> a { stPlaylistLength = x'}) x
          f a ("xfade", x)          = parse parseNum
                                      (\x' -> a { stXFadeWidth = x'}) x
          f a ("song", x)           = parse parseNum
                                      (\x' -> a { stSongPos = Just (Pos x') }) x
          f a ("songid", x)         = parse parseNum
                                      (\x' -> a { stSongID = Just (ID x') }) x
          f a ("time", x)           = parse time (\x' -> a { stTime = x' }) x
          f a ("bitrate", x)        = parse parseNum
                                      (\x' -> a { stBitrate = x'}) x
          f a ("audio", x)          = parse audio (\x' -> a { stAudio = x' }) x
          f a ("updating_db", x)    = parse parseNum
                                      (\x' -> a { stUpdatingDb = x' }) x
          f a ("error", x)          = return a { stError = x }
          f _ x                     = fail $ show x

          state "play"  = Just Playing
          state "pause" = Just Paused
          state "stop"  = Just Stopped
          state _       = Nothing

          time s = pair parseNum $ breakChar ':' s

          audio s = let (u, u') = breakChar ':' s
                        (v, w)  = breakChar ':' u' in
                    case (parseNum u, parseNum v, parseNum w) of
                        (Just a, Just b, Just c) -> Just (a, b, c)
                        _                        -> Nothing

          empty = Status Stopped 0 False False 0 0 Nothing Nothing (0,0) 0 0
                  (0,0,0) 0 ""

runParser :: (input -> Either String a) -> input -> MPD a
runParser f = either (throwError . Unexpected) return . f

-- A helper that runs a parser on a string and, depending, on the
-- outcome, either returns the result of some command applied to the
-- result, or fails. Used when building structures.
parse :: Monad m => (String -> Maybe a) -> (a -> b) -> String -> m b
parse p g x = maybe (fail x) (return . g) (p x)

-- A helper for running a parser returning Maybe on a pair of strings.
-- Returns Just if both strings where parsed successfully, Nothing otherwise.
pair :: (String -> Maybe a) -> (String, String) -> Maybe (a, a)
pair p (x, y) = case (p x, p y) of
                    (Just a, Just b) -> Just (a, b)
                    _                -> Nothing
