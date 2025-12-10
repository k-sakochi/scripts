#!/usr/bin/env nix-shell
#!nix-shell -i runghc
#!nix-shell -p haskellPackages.ghc

import Control.Monad (unless)
import Data.Char (isSpace)
import Data.List (isPrefixOf, stripPrefix, foldl')
import System.Directory (doesFileExist, getCurrentDirectory)
import System.Environment (getArgs)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO (hFlush, stdout)

expectedVars :: [String]
expectedVars =
  [ "AWS_ACCESS_KEY_ID"
  , "AWS_SECRET_ACCESS_KEY"
  , "AWS_SESSION_TOKEN"
  ]

main :: IO ()
main = do
  putStrLn "Interactive AWS env updater (Haskell edition)."
  putStrLn "Paste each value when prompted; export lines are also accepted.\n"
  pairs <- mapM promptForValue expectedVars
  args <- getArgs
  cwd <- getCurrentDirectory
  let target = case args of
        (path:_) -> path
        _ -> cwd </> "docker-compose.yml"
  exists <- doesFileExist target
  unless exists $ die ("Target file not found: " ++ target)

  contents <- readFile target
  let updatedEither = applyUpdates target contents pairs
  updated <- either die pure updatedEither
  if updated == contents
    then die "No changes applied; file already contains these values."
    else do
      writeFile target updated
      putStrLn ("Updated " ++ target ++ " with new AWS credentials.")

promptForValue :: String -> IO (String, String)
promptForValue var = do
  putStr (var ++ " > ")
  hFlush stdout
  input <- getLine
  let value = sanitizeInput var input
  if null value
    then do
      putStrLn "Value cannot be empty. Please try again."
      promptForValue var
    else pure (var, value)

sanitizeInput :: String -> String -> String
sanitizeInput var = stripQuotes . trim . dropDelims . dropVar . dropExport
  where
    dropExport txt = case stripPrefix "export" (trimLeft txt) of
      Just rest -> trimLeft rest
      Nothing -> txt
    dropVar txt =
      case stripPrefix var (trimLeft txt) of
        Just rest -> trimLeft (dropWhile (\c -> isSpace c || c == '=') rest)
        Nothing -> txt
    dropDelims txt = trimLeft (dropWhile (== '=') txt)
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
