#!/usr/bin/env nix-shell
#!nix-shell -i runghc
#!nix-shell -p haskellPackages.ghc

import Control.Monad (unless)
import Data.Char (isSpace)
import Data.List (isPrefixOf, stripPrefix, foldl')
import Data.Maybe (fromMaybe)
import System.Directory (doesFileExist, getCurrentDirectory)
import System.Environment (getArgs)
import System.Exit (ExitCode(..), die)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)
import System.Process (readProcessWithExitCode)

defaultProfile :: String
defaultProfile = "ugo-dev"

expectedVars :: [String]
expectedVars =
  [ "AWS_ACCESS_KEY_ID"
  , "AWS_SECRET_ACCESS_KEY"
  , "AWS_SESSION_TOKEN"
  ]

data Options = Options
  { optProfile :: String
  , optTarget  :: Maybe FilePath
  }

main :: IO ()
main = do
  args <- getArgs
  opts <- either die pure (parseArgs args)
  putStrLn ("Using AWS profile: " ++ optProfile opts)
  ensureLoggedIn (optProfile opts)
  pairs <- exportCredentials (optProfile opts)

  cwd <- getCurrentDirectory
  let target = fromMaybe (cwd </> "docker-compose.yml") (optTarget opts)
  exists <- doesFileExist target
  unless exists $ die ("Target file not found: " ++ target)

  contents <- readFile target
  let updatedEither = applyUpdates target contents pairs
  updated <- either die pure updatedEither
  if updated == contents
    then die "No changes applied; file already contains these values."
    else do
      length updated `seq` writeFile target updated
      putStrLn ("Updated " ++ target ++ " with new AWS credentials.")

parseArgs :: [String] -> Either String Options
parseArgs = go (Options defaultProfile Nothing)
  where
    go opts [] = Right opts
    go opts ("--profile":p:rest) = go (opts { optProfile = p }) rest
    go _    ["--profile"]        = Left "--profile requires a value"
    go opts (x:rest)
      | "--profile=" `isPrefixOf` x =
          go (opts { optProfile = drop (length ("--profile=" :: String)) x }) rest
      | "--" `isPrefixOf` x = Left ("Unknown option: " ++ x)
      | otherwise =
          case optTarget opts of
            Nothing -> go (opts { optTarget = Just x }) rest
            Just _  -> Left ("Unexpected extra argument: " ++ x)

ensureLoggedIn :: String -> IO ()
ensureLoggedIn profile = do
  putStrLn "Checking AWS SSO session..."
  (code, _out, _err) <- readProcessWithExitCode "aws"
    ["sts", "get-caller-identity", "--profile", profile]
    ""
  case code of
    ExitSuccess -> putStrLn "Already authenticated."
    _ -> do
      putStrLn "Not authenticated. Running `aws sso login`..."
      (loginCode, loginOut, loginErr) <- readProcessWithExitCode "aws"
        ["sso", "login", "--profile", profile]
        ""
      unless (null loginOut) $ putStrLn loginOut
      case loginCode of
        ExitSuccess -> putStrLn "Login succeeded."
        _ -> do
          hPutStrLn stderr loginErr
          die "Failed to login via AWS SSO."

exportCredentials :: String -> IO [(String, String)]
exportCredentials profile = do
  putStrLn "Exporting credentials..."
  (code, out, err) <- readProcessWithExitCode "aws"
    ["configure", "export-credentials", "--profile", profile, "--format", "env"]
    ""
  case code of
    ExitSuccess -> do
      let pairs = parseEnvExport out
          missing = [v | v <- expectedVars, lookup v pairs == Nothing]
      unless (null missing) $
        die ("Missing credentials in export output: " ++ unwords missing)
      pure [(v, val) | v <- expectedVars, Just val <- [lookup v pairs]]
    _ -> do
      hPutStrLn stderr err
      die "Failed to export AWS credentials."

parseEnvExport :: String -> [(String, String)]
parseEnvExport = foldr parseLine [] . lines
  where
    parseLine raw acc =
      let stripped = dropExport (trimLeft raw)
       in case break (== '=') stripped of
            (name, '=':rest) ->
              let key = trim name
                  value = stripQuotes (trim rest)
               in if null key then acc else (key, value) : acc
            _ -> acc
    dropExport txt = case stripPrefix "export" txt of
      Just rest@(c:_) | isSpace c -> trimLeft rest
      _ -> txt
    trimLeft = dropWhile isSpace

stripQuotes :: String -> String
stripQuotes s
  | len >= 2 && head s == '"' && last s == '"' = take (len - 2) (tail s)
  | len >= 2 && head s == '\'' && last s == '\'' = take (len - 2) (tail s)
  | otherwise = s
  where
    len = length s

trim :: String -> String
trim = dropWhileEnd isSpace . dropWhile isSpace

-- | dropWhileEnd compatible helper (pre-base 4.16)
dropWhileEnd :: (a -> Bool) -> [a] -> [a]
dropWhileEnd p = foldr f []
  where
    f x xs
      | p x && null xs = []
      | otherwise = x : xs

applyUpdates :: FilePath -> String -> [(String, String)] -> Either String String
applyUpdates target contents pairs = foldl' step (Right contents) pairs
  where
    step (Left err) _ = Left err
    step (Right current) (var, value) = replaceVar target var value current

replaceVar :: FilePath -> String -> String -> String -> Either String String
replaceVar target var value contents =
  let (resultLines, replaced) = foldl' (processLine var value) ([], False) (lines contents)
   in if replaced
        then Right (unlines (reverse resultLines))
        else Left ("Could not find " ++ var ++ " entry inside " ++ target)

processLine :: String -> String -> ([String], Bool) -> String -> ([String], Bool)
processLine var value (acc, already) line
  | already = (line : acc, already)
  | otherwise =
      let trimmed = dropWhile isSpace line
          trimmed' =
            case trimmed of
              ('#':rest) -> dropWhile isSpace rest
              _ -> trimmed
          prefix = var ++ ":"
       in if prefix `isPrefixOf` trimmed'
            then
              let leading = takeWhile isSpace line
                  newLine = leading ++ var ++ ": " ++ value
               in (newLine : acc, True)
            else (line : acc, False)
