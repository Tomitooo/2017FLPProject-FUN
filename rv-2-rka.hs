import Options.Applicative;
import Data.Semigroup ((<>))
import Control.Monad
import System.IO
import Data.Either
import System.Exit (exitWith)

import Types


{----------------------------------------------------------- 
        COMMANDLINE ENTRY POINT & ARGUMENTS PROCESSING 
------------------------------------------------------------}

main :: IO ()
main = do
  processInput =<< execParser opts
      where
        opts = info (parameterDefinitions <**> helper)
          ( fullDesc
         <> progDesc "Reads regular expression in reverse polish notation (postfix) from input file and based on -r|-t switch displays or transforms it to finite state machine-"
         <> header "Converts regex from the input to finite state machine on output." )  

parameterDefinitions :: Parser Arguments
parameterDefinitions = Arguments
      <$> (parseRepresent <|> parseTransform)
      <*> argument str (metavar "FILE" <> value "")
  where
    parseRepresent = flag' Represent
        ( long "represent" 
        <> short 'r' 
        <> help "Converts regular expression from input to internal representation and prints it out of it."
        )

    parseTransform = flag' Transform
        ( long "transform" 
        <> short 't' 
        <> help "Converts regular expression from input to finite state machine on output."
        )

{-- Based on chosen flag calls for corresponding processing function --}
processInput :: Arguments -> IO ()
processInput (Arguments a file) = case a of
    Represent -> demonstrateRegexRepresentation file
    Transform -> transformRV2FSM file 


{----------------------------------------------------------- 
        INPUT PARSING & OUTPUT FORMATTING FUNCTIONS 
------------------------------------------------------------}

{-- 
    Content serving IO functions for both -r and -t switches
    Note: I designed these functions to be the only ones interacting with IO, hence the $-madness on their last lines 
--}
demonstrateRegexRepresentation :: String -> IO ()
demonstrateRegexRepresentation file = do
  content <- readFile file
  putStrLn $ reverse $ representTree' $ head $ map readRPNRegex $ lines content

transformRV2FSM :: String -> IO ()
transformRV2FSM file = do
    content <- readFile file
    putStrLn  $ rv2rka' $ head $ map readRPNRegex $ lines content

{-- 
    Input regex parsing functions
    Inspired by: * http://stackoverflow.com/questions/36277160/haskell-reverse-polish-notation-regular-expression-to-expression-tree
                 * Also from Ing. Marek Kidon consultations
    Extra mile: Function is actually capable of determining (and reacting) on invalid regex on input (i.e. for ab++ prints information about invalid input)
--}
readRPNRegex :: String -> Either String Tree
readRPNRegex s = case foldM parseCharacter' [] s of 
  Right [e]  -> Right e
  Left  e    -> Left e
  _          -> Left regexNotValid
  where
    parseCharacter' (r:l:s)  '.'   =  Right $ (BinaryOperation '.' l r):s
    parseCharacter' (r:l:s)  '+'   =  Right $ (BinaryOperation '+' l r):s
    parseCharacter' (r:s)    '*'   =  Right $ (Star '*' r):s
    parseCharacter' s c 
                        | c == '.' || c == '+' || c == '*' = Left $ regexNotValid
                        | True = Right $ (Character c):s

{-- 
    Regex tree representation functions (-r switch) 
--}
representTree' :: Either String Tree -> String 
representTree' (Left e) = reverse e
representTree' (Right t) = representTree t 

representTree :: Tree -> String 
representTree (Character c) = [c]
representTree (Star c tree) = c : (representTree tree)
representTree (BinaryOperation c leftTree rightTree) =  c :  (representTree  rightTree) ++ (representTree leftTree)   

{--
    FSM transformation functions (-t switch)
--}
rv2rka' :: Either String Tree -> String 
rv2rka' (Left e) = e
rv2rka' (Right t) = show $ rv2rka t

rv2rka :: Tree -> FSM
rv2rka (Character a) = FSM [1,2] [] [TTransition 1 (TransitionLabel a) 2] 1 [2] -- Only basic automaton for 'a'
rv2rka (BinaryOperation '+' leftTree rightTree) = constructUnion (rv2rka leftTree) (rv2rka rightTree)
rv2rka (BinaryOperation '.' leftTree rightTree) = constructConcat (rv2rka leftTree) (rv2rka rightTree)
rv2rka (Star '*' tree) = constructIteration $ rv2rka tree
rv2rka t =  FSM [] [] [] 0 []


{----------------------------------------------------------- 
          REGEX TO FSM ALGORITHM FUNCTIONS
Algorithm I followed is described in README documentation(s) 
------------------------------------------------------------}

{-- 
    Reusable FSM construction helper functions 
--}
shiftTransition :: Int -> TTransition -> TTransition
shiftTransition shift (TTransition f s t) = (TTransition (f+shift) s (t+shift)) 

{--
  Functions for Union, Concatenation and Iteration of FSMs 
--}
constructUnion :: FSM -> FSM -> FSM
constructUnion (FSM aS _ aT aIS aFS) (FSM bS _ bT bIS bFS) = FSM ([1] ++ generateNewStates) [] generateNewTransitions 1 [newFinalState]
  where
    generateNewStates = map (+1) aS ++ map (+ (1 + length aS)) bS ++ [newFinalState]
    newFinalState = 2 + (length $ aS ++ bS)
    generateNewTransitions = (map (shiftTransition 1) aT) ++ (map (shiftTransition (1 + length aS)) bT) ++ generateEpsilonTransitions
    generateEpsilonTransitions = [TTransition 1 Epsilon (aIS + 1), TTransition 1 Epsilon (bIS + 1 + length aS)] ++ map (\s -> TTransition s Epsilon newFinalState) (map (+1) aFS ++  map (+ (1 + length aS)) bFS)

constructConcat :: FSM -> FSM -> FSM
constructConcat (FSM aS _ aT aIS aFS) (FSM bS _ bT bIS bFS) = FSM (generateNewStates) [] generateNewTransitions 1 [newFinalState]
  where 
    generateNewStates = aS ++ [1 + length aS] ++ map (+ (1 + length aS)) bS
    newFinalState = last generateNewStates
    generateNewTransitions = aT ++ (map (shiftTransition (1 + length aS)) bT) ++ [TTransition (length aS) Epsilon (1 + length aS), TTransition (1 + length aS) Epsilon (2 + length aS)]

constructIteration :: FSM -> FSM
constructIteration (FSM aS _ aT aIS aFS) = FSM ([1] ++ generateNewStates) [] generateNewTransitions 1 [newFinalState]
  where
    generateNewStates = map (+1) aS ++ [newFinalState]
    newFinalState = 2 + length (aS) 
    generateNewTransitions = map (shiftTransition 1) aT ++ map (\s -> TTransition s Epsilon newFinalState) (map (+1) aFS)  ++ [TTransition 1 Epsilon 2, TTransition newFinalState Epsilon 1, TTransition 1 Epsilon newFinalState] 