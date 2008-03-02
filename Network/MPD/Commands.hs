{-
    libmpd for Haskell, an MPD client library.
    Copyright (C) 2005-2008  Ben Sinclair <bsinclai@turing.une.edu.au>

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
-}

-- | Module    : Network.MPD.Commands
-- Copyright   : (c) Ben Sinclair 2005-2008
-- License     : LGPL
-- Maintainer  : bsinclai@turing.une.edu.au
-- Stability   : alpha
-- Portability : Haskell 98
--
-- Interface to the user commands supported by MPD.

module Network.MPD.Commands (
    -- * Command related data types
    State(..), Status(..), Stats(..),
    Device(..),
    Query(..), Meta(..),
    Artist, Album, Title, Seconds, PlaylistName, Path,
    PLIndex(..), Song(..), Count(..),

    -- * Admin commands
    disableOutput, enableOutput, kill, outputs, update,

    -- * Database commands
    find, list, listAll, listAllInfo, lsInfo, search, count,

    -- * Playlist commands
    -- $playlist
    add, add_, addId, clear, currentSong, delete, load, move,
    playlistInfo, listPlaylist, listPlaylistInfo, playlist, plChanges,
    plChangesPosId, playlistFind, playlistSearch, rm, rename, save, shuffle,
    swap,

    -- * Playback commands
    crossfade, next, pause, play, previous, random, repeat, seek, setVolume,
    volume, stop,

    -- * Miscellaneous commands
    clearError, close, commands, notCommands, password, ping, reconnect, stats,
    status, tagTypes, urlHandlers,

    -- * Extensions\/shortcuts
    addMany, deleteMany, complete, crop, prune, lsDirs, lsFiles, lsPlaylists,
    findArtist, findAlbum, findTitle, listArtists, listAlbums, listAlbum,
    searchArtist, searchAlbum, searchTitle, getPlaylist, toggle, updateId
    ) where

import Network.MPD.Core
import Network.MPD.Utils

import Control.Monad (foldM, liftM, unless)
import Control.Monad.Error (throwError)
import Prelude hiding (repeat)
import Data.List (findIndex, intersperse, isPrefixOf)
import Data.Maybe
import System.FilePath (dropFileName)

--
-- Data types
--

type Artist       = String
type Album        = String
type Title        = String
type Seconds      = Integer

-- | Used for commands which require a playlist name.
-- If empty, the current playlist is used.
type PlaylistName = String

-- | Used for commands which require a path within the database.
-- If empty, the root path is used.
type Path         = String

-- | Available metadata types\/scope modifiers, used for searching the
-- database for entries with certain metadata values.
data Meta = Artist | Album | Title | Track | Name | Genre | Date
    | Composer | Performer | Disc | Any | Filename

instance Show Meta where
    show Artist    = "Artist"
    show Album     = "Album"
    show Title     = "Title"
    show Track     = "Track"
    show Name      = "Name"
    show Genre     = "Genre"
    show Date      = "Date"
    show Composer  = "Composer"
    show Performer = "Performer"
    show Disc      = "Disc"
    show Any       = "Any"
    show Filename  = "Filename"

-- | A query is composed of a scope modifier and a query string.
--
-- To match entries where album equals \"Foo\", use:
--
-- > Query Album "Foo"
--
-- To match entries where album equals \"Foo\" and artist equals \"Bar\", use:
--
-- > MultiQuery [Query Album "Foo", Query Artist "Bar"]
data Query = Query Meta String  -- ^ Simple query.
           | MultiQuery [Query] -- ^ Query with multiple conditions.

instance Show Query where
    show (Query meta query) = show meta ++ " " ++ show query
    show (MultiQuery xs)    = show xs
    showList xs _ = unwords $ map show xs

-- | Represents a song's playlist index.
data PLIndex = Pos Integer -- ^ A playlist position index (starting from 0)
             | ID Integer  -- ^ A playlist ID number that more robustly
                           --   identifies a song.
    deriving Show

-- | Represents the different playback states.
data State = Playing
           | Stopped
           | Paused
    deriving (Show, Eq)

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
    deriving Show

-- | Represents a single song item.
data Song =
    Song { sgArtist, sgAlbum, sgTitle, sgFilePath, sgGenre, sgName, sgComposer
         , sgPerformer :: String
         , sgLength    :: Seconds       -- ^ Length in seconds
         , sgDate      :: Int           -- ^ Year
         , sgTrack     :: (Int, Int)    -- ^ Track number\/total tracks
         , sgDisc      :: (Int, Int)    -- ^ Position in set\/total in set
         , sgIndex     :: Maybe PLIndex }
    deriving Show

-- Avoid the need for writing a proper 'elem' for use in 'prune'.
instance Eq Song where
    (==) x y = sgFilePath x == sgFilePath y

-- | Represents the result of running 'count'.
data Count =
    Count { cSongs    :: Integer -- ^ Number of songs matching the query
          , cPlaytime :: Seconds -- ^ Total play time of matching songs
          }
    deriving (Eq, Show)

-- | Represents an output device.
data Device =
    Device { dOutputID      :: Int    -- ^ Output's ID number
           , dOutputName    :: String -- ^ Output's name as defined in the MPD
                                      --   configuration file
           , dOutputEnabled :: Bool }
    deriving (Eq, Show)

--
-- Admin commands
--

-- | Turn off an output device.
disableOutput :: Int -> MPD ()
disableOutput = getResponse_ . ("disableoutput " ++) . show

-- | Turn on an output device.
enableOutput :: Int -> MPD ()
enableOutput = getResponse_ . ("enableoutput " ++) . show

-- | Retrieve information for all output devices.
outputs :: MPD [Device]
outputs = liftM (map takeDevInfo . splitGroups . toAssoc)
    (getResponse "outputs")
    where
        takeDevInfo xs = Device {
            dOutputID      = takeNum "outputid" xs,
            dOutputName    = takeString "outputname" xs,
            dOutputEnabled = takeBool "outputenabled" xs
            }

-- | Update the server's database.
-- If no paths are given, all paths will be scanned.
-- Unreadable or non-existent paths are silently ignored.
update :: [Path] -> MPD ()
update  [] = getResponse_ "update"
update [x] = getResponse_ ("update " ++ show x)
update  xs = getResponses (map (("update " ++) . show) xs) >> return ()

--
-- Database commands
--

-- | List all metadata of metadata (sic).
list :: Meta -- ^ Metadata to list
     -> Maybe Query -> MPD [String]
list mtype query = liftM takeValues (getResponse cmd)
    where cmd = "list " ++ show mtype ++ maybe "" ((" "++) . show) query

-- | Non-recursively list the contents of a database directory.
lsInfo :: Path -> MPD [Either Path Song]
lsInfo = lsInfo' "lsinfo"

-- | List the songs (without metadata) in a database directory recursively.
listAll :: Path -> MPD [Path]
listAll path = liftM (map snd . filter ((== "file") . fst) . toAssoc)
                     (getResponse ("listall " ++ show path))

-- | Recursive 'lsInfo'.
listAllInfo :: Path -> MPD [Either Path Song]
listAllInfo = lsInfo' "listallinfo"

-- Helper for lsInfo and listAllInfo.
lsInfo' :: String -> Path -> MPD [Either Path Song]
lsInfo' cmd path = do
    (dirs,_,songs) <- takeEntries =<< getResponse (cmd ++ " " ++ show path)
    return (map Left dirs ++ map Right songs)

-- | Search the database for entries exactly matching a query.
find :: Query -> MPD [Song]
find query = getResponse ("find " ++ show query) >>= takeSongs

-- | Search the database using case insensitive matching.
search :: Query -> MPD [Song]
search query = getResponse ("search " ++ show query) >>= takeSongs

-- | Count the number of entries matching a query.
count :: Query -> MPD Count
count query = getResponse ("count " ++ show query) >>=
              foldM f empty . toAssoc
    where f a ("songs", x)    = parse parseNum
                                (\x' -> a { cSongs = x'}) x
          f a ("playtime", x) = parse parseNum
                                (\x' -> a { cPlaytime = x' }) x
          f _ x               = throwError . Unexpected $ show x
          empty = Count { cSongs = 0, cPlaytime = 0 }

--
-- Playlist commands
--
-- $playlist
-- Unless otherwise noted all playlist commands operate on the current
-- playlist.

-- This might do better to throw an exception than silently return 0.
-- | Like 'add', but returns a playlist id.
addId :: Path -> MPD Integer
addId = liftM (takeNum "Id" . toAssoc) . getResponse . ("addid " ++) . show

-- | Like 'add_' but returns a list of the files added.
add :: PlaylistName -> Path -> MPD [Path]
add plname x = add_ plname x >> listAll x

-- | Add a song (or a whole directory) to a playlist.
-- Adds to current if no playlist is specified.
-- Will create a new playlist if the one specified does not already exist.
add_ :: PlaylistName -> Path -> MPD ()
add_ ""     = getResponse_ . ("add " ++) . show
add_ plname = getResponse_ .
    (("playlistadd " ++ show plname ++ " ") ++) . show

-- | Clear a playlist. Clears current playlist if no playlist is specified.
-- If the specified playlist does not exist, it will be created.
clear :: PlaylistName -> MPD ()
clear = getResponse_ . cmd
    where cmd "" = "clear"
          cmd pl = "playlistclear " ++ show pl

-- | Remove a song from a playlist.
-- If no playlist is specified, current playlist is used.
-- Note that a playlist position ('Pos') is required when operating on
-- playlists other than the current.
delete :: PlaylistName -> PLIndex -> MPD ()
delete "" (Pos x) = getResponse_ ("delete " ++ show x)
delete "" (ID x)  = getResponse_ ("deleteid " ++ show x)
delete plname (Pos x) =
    getResponse_ ("playlistdelete " ++ show plname ++ " " ++ show x)
delete _ _ = fail "'delete' within a playlist doesn't accept a playlist ID"

-- | Load an existing playlist.
load :: PlaylistName -> MPD ()
load = getResponse_ . ("load " ++) . show

-- | Move a song to a given position.
-- Note that a playlist position ('Pos') is required when operating on
-- playlists other than the current.
move :: PlaylistName -> PLIndex -> Integer -> MPD ()
move "" (Pos from) to =
    getResponse_ ("move " ++ show from ++ " " ++ show to)
move "" (ID from) to =
    getResponse_ ("moveid " ++ show from ++ " " ++ show to)
move plname (Pos from) to =
    getResponse_ ("playlistmove " ++ show plname ++ " " ++ show from ++
                       " " ++ show to)
move _ _ _ = fail "'move' within a playlist doesn't accept a playlist ID"

-- | Delete existing playlist.
rm :: PlaylistName -> MPD ()
rm = getResponse_ . ("rm " ++) . show

-- | Rename an existing playlist.
rename :: PlaylistName -- ^ Original playlist
       -> PlaylistName -- ^ New playlist name
       -> MPD ()
rename plname new =
    getResponse_ ("rename " ++ show plname ++ " " ++ show new)

-- | Save the current playlist.
save :: PlaylistName -> MPD ()
save = getResponse_ . ("save " ++) . show

-- | Swap the positions of two songs.
-- Note that the positions must be of the same type, i.e. mixing 'Pos' and 'ID'
-- will result in a no-op.
swap :: PLIndex -> PLIndex -> MPD ()
swap (Pos x) (Pos y) = getResponse_ ("swap "   ++ show x ++ " " ++ show y)
swap (ID x)  (ID y)  = getResponse_ ("swapid " ++ show x ++ " " ++ show y)
swap _ _ = fail "'swap' cannot mix position and ID arguments"

-- | Shuffle the playlist.
shuffle :: MPD ()
shuffle = getResponse_ "shuffle"

-- | Retrieve metadata for songs in the current playlist.
playlistInfo :: Maybe PLIndex -> MPD [Song]
playlistInfo x = getResponse cmd >>= takeSongs
    where cmd = case x of
                    Just (Pos x') -> "playlistinfo " ++ show x'
                    Just (ID x')  -> "playlistid " ++ show x'
                    Nothing       -> "playlistinfo"

-- | Retrieve metadata for files in a given playlist.
listPlaylistInfo :: PlaylistName -> MPD [Song]
listPlaylistInfo plname =
    takeSongs =<< (getResponse . ("listplaylistinfo " ++) $ show plname)

-- | Retrieve a list of files in a given playlist.
listPlaylist :: PlaylistName -> MPD [Path]
listPlaylist = liftM takeValues . getResponse . ("listplaylist " ++) . show

-- | Retrieve file paths and positions of songs in the current playlist.
-- Note that this command is only included for completeness sake; it's
-- deprecated and likely to disappear at any time, please use 'playlistInfo'
-- instead.
playlist :: MPD [(PLIndex, Path)]
playlist = liftM (map f) (getResponse "playlist")
    where f s = let (pos, name) = break (== ':') s
                in (Pos $ read pos, drop 1 name)

-- | Retrieve a list of changed songs currently in the playlist since
-- a given playlist version.
plChanges :: Integer -> MPD [Song]
plChanges version =
    takeSongs =<< (getResponse . ("plchanges " ++) $ show version)

-- | Like 'plChanges' but only returns positions and ids.
plChangesPosId :: Integer -> MPD [(PLIndex, PLIndex)]
plChangesPosId plver =
    liftM (map takePosid . splitGroups . toAssoc) (getResponse cmd)
    where cmd          = "plchangesposid " ++ show plver
          takePosid xs = (Pos $ takeNum "cpos" xs, ID $ takeNum "Id" xs)

-- | Search for songs in the current playlist with strict matching.
playlistFind :: Query -> MPD [Song]
playlistFind q = takeSongs =<< (getResponse . ("playlistfind " ++) $ show q)

-- | Search case-insensitively with partial matches for songs in the
-- current playlist.
playlistSearch :: Query -> MPD [Song]
playlistSearch q =
    takeSongs =<< (getResponse . ("playlistsearch " ++) $ show q)

-- | Get the currently playing song.
currentSong :: MPD (Maybe Song)
currentSong = do
    currStatus <- status
    if stState currStatus == Stopped
        then return Nothing
        else do ls <- liftM toAssoc (getResponse "currentsong")
                if null ls then return Nothing
                           else liftM Just (takeSongInfo ls)

--
-- Playback commands
--

-- | Set crossfading between songs.
crossfade :: Seconds -> MPD ()
crossfade = getResponse_ . ("crossfade " ++) . show

-- | Begin\/continue playing.
play :: Maybe PLIndex -> MPD ()
play Nothing        = getResponse_ "play"
play (Just (Pos x)) = getResponse_ ("play " ++ show x)
play (Just (ID x))  = getResponse_ ("playid " ++ show x)

-- | Pause playing.
pause :: Bool -> MPD ()
pause = getResponse_ . ("pause " ++) . showBool

-- | Stop playing.
stop :: MPD ()
stop = getResponse_ "stop"

-- | Play the next song.
next :: MPD ()
next = getResponse_ "next"

-- | Play the previous song.
previous :: MPD ()
previous = getResponse_ "previous"

-- | Seek to some point in a song.
-- Seeks in current song if no position is given.
seek :: Maybe PLIndex -> Seconds -> MPD ()
seek (Just (Pos x)) time =
    getResponse_ ("seek " ++ show x ++ " " ++ show time)
seek (Just (ID x)) time =
    getResponse_ ("seekid " ++ show x ++ " " ++ show time)
seek Nothing time = do
    st <- status
    unless (stState st == Stopped) (seek (stSongID st) time)

-- | Set random playing.
random :: Bool -> MPD ()
random = getResponse_ . ("random " ++) . showBool

-- | Set repeating.
repeat :: Bool -> MPD ()
repeat = getResponse_ . ("repeat " ++) . showBool

-- | Set the volume (0-100 percent).
setVolume :: Int -> MPD ()
setVolume = getResponse_ . ("setvol " ++) . show

-- | Increase or decrease volume by a given percent, e.g.
-- 'volume 10' will increase the volume by 10 percent, while
-- 'volume (-10)' will decrease it by the same amount.
-- Note that this command is only included for completeness sake ; it's
-- deprecated and may disappear at any time, please use 'setVolume' instead.
volume :: Int -> MPD ()
volume = getResponse_ . ("volume " ++) . show

--
-- Miscellaneous commands
--

-- | Clear the current error message in status.
clearError :: MPD ()
clearError = getResponse_ "clearerror"

-- | Retrieve a list of available commands.
commands :: MPD [String]
commands = liftM takeValues (getResponse "commands")

-- | Retrieve a list of unavailable (due to access restrictions) commands.
notCommands :: MPD [String]
notCommands = liftM takeValues (getResponse "notcommands")

-- | Retrieve a list of available song metadata.
tagTypes :: MPD [String]
tagTypes = liftM takeValues (getResponse "tagtypes")

-- | Retrieve a list of supported urlhandlers.
urlHandlers :: MPD [String]
urlHandlers = liftM takeValues (getResponse "urlhandlers")

-- XXX should the password be quoted?
-- | Send password to server to authenticate session.
-- Password is sent as plain text.
password :: String -> MPD ()
password = getResponse_ . ("password " ++)

-- | Check that the server is still responding.
ping :: MPD ()
ping = getResponse_ "ping"

-- | Get server statistics.
stats :: MPD Stats
stats = getResponse "stats" >>= foldM f defaultStats . toAssoc
    where
        f a ("artists", x)  = parse parseNum (\x' -> a { stsArtists  = x' }) x
        f a ("albums", x)   = parse parseNum (\x' -> a { stsAlbums   = x' }) x
        f a ("songs", x)    = parse parseNum (\x' -> a { stsSongs    = x' }) x
        f a ("uptime", x)   = parse parseNum (\x' -> a { stsUptime   = x' }) x
        f a ("playtime", x) = parse parseNum (\x' -> a { stsPlaytime = x' }) x
        f a ("db_playtime", x) = parse parseNum
                                 (\x' -> a { stsDbPlaytime = x' }) x
        f a ("db_update", x) = parse parseNum (\x' -> a { stsDbUpdate = x' }) x
        f _ x = throwError . Unexpected $ show x
        defaultStats =
            Stats { stsArtists = 0, stsAlbums = 0, stsSongs = 0, stsUptime = 0
                  , stsPlaytime = 0, stsDbPlaytime = 0, stsDbUpdate = 0 }

-- | Get the server's status.
status :: MPD Status
status = getResponse "status" >>= foldM f empty . toAssoc
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
          f _ x                     = throwError . Unexpected $ show x

          state "play"  = Just Playing
          state "pause" = Just Paused
          state "stop"  = Just Stopped
          state _       = Nothing

          time s = let (y,_:z) = break (== ':') s in pair parseNum (y, z)

          audio s = let (u,_:u') = break (== ':') s
                        (v,_:w)  = break (== ':') u' in
                    case (parseNum u, parseNum v, parseNum w) of
                        (Just a, Just b, Just c) -> Just (a, b, c)
                        _                        -> Nothing

          empty = Status Stopped 0 False False 0 0 Nothing Nothing (0,0) 0 0
                  (0,0,0) 0 ""

--
-- Extensions\/shortcuts.
--

-- | Like 'update', but returns the update job id.
updateId :: [Path] -> MPD Integer
updateId paths = liftM (read . head . takeValues) cmd
  where cmd = case paths of
                []  -> getResponse "update"
                [x] -> getResponse ("update " ++ x)
                xs  -> getResponses (map ("update " ++) xs)

-- | Toggles play\/pause. Plays if stopped.
toggle :: MPD ()
toggle = status >>= \st -> case stState st of Playing -> pause True
                                              _       -> play Nothing

-- | Add a list of songs\/folders to a playlist.
-- Should be more efficient than running 'add' many times.
addMany :: PlaylistName -> [Path] -> MPD ()
addMany _ [] = return ()
addMany plname [x] = add_ plname x
addMany plname xs = getResponses (map ((cmd ++) . show) xs) >> return ()
    where cmd = case plname of "" -> "add "
                               pl -> "playlistadd " ++ show pl ++ " "

-- | Delete a list of songs from a playlist.
-- If there is a duplicate then no further songs will be deleted, so
-- take care to avoid them (see 'prune' for this).
deleteMany :: PlaylistName -> [PLIndex] -> MPD ()
deleteMany _ [] = return ()
deleteMany plname [x] = delete plname x
deleteMany "" xs = getResponses (map cmd xs) >> return ()
    where cmd (Pos x) = "delete " ++ show x
          cmd (ID x)  = "deleteid " ++ show x
deleteMany plname xs = getResponses (map cmd xs) >> return ()
    where cmd (Pos x) = "playlistdelete " ++ show plname ++ " " ++ show x
          cmd _       = ""

-- | Returns all songs and directories that match the given partial
-- path name.
complete :: String -> MPD [Either Path Song]
complete path = do
    xs <- liftM matches . lsInfo $ dropFileName path
    case xs of
        [Left dir] -> complete $ dir ++ "/"
        _          -> return xs
    where
        matches = filter (isPrefixOf path . takePath)
        takePath = either id sgFilePath

-- | Crop playlist.
-- The bounds are inclusive.
-- If 'Nothing' or 'ID' is passed the cropping will leave your playlist alone
-- on that side.
crop :: Maybe PLIndex -> Maybe PLIndex -> MPD ()
crop x y = do
    pl <- playlistInfo Nothing
    let x' = case x of Just (Pos p) -> fromInteger p
                       Just (ID i)  -> maybe 0 id (findByID i pl)
                       Nothing      -> 0
        -- ensure that no songs are deleted twice with 'max'.
        ys = case y of Just (Pos p) -> drop (max (fromInteger p) x') pl
                       Just (ID i)  -> maybe [] (flip drop pl . max x' . (+1))
                                      (findByID i pl)
                       Nothing      -> []
    deleteMany "" . mapMaybe sgIndex $ take x' pl ++ ys
    where findByID i = findIndex ((==) i . (\(ID j) -> j) . fromJust . sgIndex)

-- | Remove duplicate playlist entries.
prune :: MPD ()
prune = findDuplicates >>= deleteMany ""

-- Find duplicate playlist entries.
findDuplicates :: MPD [PLIndex]
findDuplicates =
    liftM (map ((\(ID x) -> ID x) . fromJust . sgIndex) . flip dups ([],[])) $
        playlistInfo Nothing
    where dups [] (_, dup) = dup
          dups (x:xs) (ys, dup)
              | x `elem` xs && x `notElem` ys = dups xs (ys, x:dup)
              | otherwise                     = dups xs (x:ys, dup)

-- | List directories non-recursively.
lsDirs :: Path -> MPD [Path]
lsDirs path = liftM (\(x,_,_) -> x) $
              takeEntries =<< getResponse ("lsinfo " ++ show path)

-- | List files non-recursively.
lsFiles :: Path -> MPD [Path]
lsFiles path = liftM (map sgFilePath . (\(_,_,x) -> x)) $
               takeEntries =<< getResponse ("lsinfo " ++ show path)

-- | List all playlists.
lsPlaylists :: MPD [PlaylistName]
lsPlaylists = liftM (\(_,x,_) -> x) $ takeEntries =<< getResponse "lsinfo"

-- | Search the database for songs relating to an artist.
findArtist :: Artist -> MPD [Song]
findArtist = find . Query Artist

-- | Search the database for songs relating to an album.
findAlbum :: Album -> MPD [Song]
findAlbum = find . Query Album

-- | Search the database for songs relating to a song title.
findTitle :: Title -> MPD [Song]
findTitle = find . Query Title

-- | List the artists in the database.
listArtists :: MPD [Artist]
listArtists = liftM takeValues (getResponse "list artist")

-- | List the albums in the database, optionally matching a given
-- artist.
listAlbums :: Maybe Artist -> MPD [Album]
listAlbums artist = liftM takeValues (getResponse ("list album" ++
    maybe "" ((" artist " ++) . show) artist))

-- | List the songs in an album of some artist.
listAlbum :: Artist -> Album -> MPD [Song]
listAlbum artist album = find (MultiQuery [Query Artist artist
                                          ,Query Album album])

-- | Search the database for songs relating to an artist using 'search'.
searchArtist :: Artist -> MPD [Song]
searchArtist = search . Query Artist

-- | Search the database for songs relating to an album using 'search'.
searchAlbum :: Album -> MPD [Song]
searchAlbum = search . Query Album

-- | Search the database for songs relating to a song title.
searchTitle :: Title -> MPD [Song]
searchTitle = search . Query Title

-- | Retrieve the current playlist.
-- Equivalent to @playlistinfo Nothing@.
getPlaylist :: MPD [Song]
getPlaylist = playlistInfo Nothing

--
-- Miscellaneous functions.
--

-- Run getResponse but discard the response.
getResponse_ :: String -> MPD ()
getResponse_ x = getResponse x >> return ()

-- Get the lines of the daemon's response to a list of commands.
getResponses :: [String] -> MPD [String]
getResponses cmds = getResponse . concat $ intersperse "\n" cmds'
    where cmds' = "command_list_begin" : cmds ++ ["command_list_end"]

-- Helper that throws unexpected error if input is empty.
failOnEmpty :: [String] -> MPD [String]
failOnEmpty [] = throwError $ Unexpected "Non-empty response expected."
failOnEmpty xs = return xs

-- A wrapper for getResponse that fails on non-empty responses.
getResponse1 :: String -> MPD [String]
getResponse1 x = getResponse x >>= failOnEmpty

-- getResponse1 for multiple commands.
getResponses1 :: [String] -> MPD [String]
getResponses1 cmds = getResponses cmds >>= failOnEmpty

--
-- Parsing.
--

-- Run 'toAssoc' and return only the values.
takeValues :: [String] -> [String]
takeValues = snd . unzip . toAssoc

-- Separate the result of an lsinfo\/listallinfo call into directories,
-- playlists, and songs.
takeEntries :: [String] -> MPD ([String], [String], [Song])
takeEntries s = do
    ss <- mapM takeSongInfo . splitGroups $ reverse filedata
    return (dirs, playlists, ss)
    where (dirs, playlists, filedata) = foldl split ([], [], []) $ toAssoc s
          split (ds, pls, ss) x@(k, v) | k == "directory" = (v:ds, pls, ss)
                                       | k == "playlist"  = (ds, v:pls, ss)
                                       | otherwise        = (ds, pls, x:ss)

-- Build a list of song instances from a response.
takeSongs :: [String] -> MPD [Song]
takeSongs = mapM takeSongInfo . splitGroups . toAssoc

-- Builds a song instance from an assoc. list.
takeSongInfo :: [(String, String)] -> MPD Song
takeSongInfo xs = foldM f song xs
    where f a ("Artist", x)    = return a { sgArtist = x }
          f a ("Album", x)     = return a { sgAlbum  = x }
          f a ("Title", x)     = return a { sgTitle = x }
          f a ("Genre", x)     = return a { sgGenre = x }
          f a ("Name", x)      = return a { sgName = x }
          f a ("Composer", x)  = return a { sgComposer = x }
          f a ("Performer", x) = return a { sgPerformer = x }
          f a ("Date", x)      = parse parseNum (\x' -> a { sgDate = x'}) x
          f a ("Track", x)     = parse parseTuple (\x' -> a { sgTrack = x'}) x
          f a ("Disc", x)      = parse parseTuple (\x' -> a { sgDisc = x'}) x
          f a ("file", x)      = return a { sgFilePath = x }
          f a ("Time", x)      = parse parseNum (\x' -> a { sgLength = x'}) x
          f a ("Id", x)        = parse parseNum
                                 (\x' -> a { sgIndex = Just (ID x') }) x
          -- We prefer Id.
          f a ("Pos", _)       = return a
          -- Catch unrecognised keys
          f _ x                = throwError (Unexpected (show x))

          parseTuple s = pair parseNum $ break (== '/') s

          song = Song { sgArtist = "", sgAlbum = "", sgTitle = ""
                      , sgGenre = "", sgName = "", sgComposer = ""
                      , sgPerformer = "", sgDate = 0, sgTrack = (0,0)
                      , sgDisc = (0,0), sgFilePath = "", sgLength = 0
                      , sgIndex = Nothing }

-- A helper that runs a parser on a string and, depending, on the outcome,
-- either returns the result of some command applied to the result, or throws
-- an Unexpected error. Used when building structures.
parse :: (String -> Maybe a) -> (a -> b) -> String -> MPD b
parse p g x = maybe (throwError $ Unexpected x) (return . g) (p x)

-- A helper for running a parser returning Maybe on a pair of strings.
-- Returns Just if both strings where parsed successfully, Nothing otherwise.
pair :: (String -> Maybe a) -> (String, String) -> Maybe (a, a)
pair p (x, y) = case (p x, p y) of
                    (Just a, Just b) -> Just (a, b)
                    _                -> Nothing

-- Helpers for retrieving values from an assoc. list.

takeNum :: (Read a, Integral a) => String -> [(String, String)] -> a
takeNum v = maybe 0 (fromMaybe 0 . parseNum) . lookup v

takeBool :: String -> [(String, String)] -> Bool
takeBool v = maybe False (fromMaybe False . parseBool) . lookup v

takeString :: String -> [(String, String)] -> String
takeString v = fromMaybe "" . lookup v
