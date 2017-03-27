{- A basic Streaming NESL interpreter

+ reused code from unesl interpreter
+ time cost(work and step) not guaranteed
+ space cost not added
-}

module SneslInterp where

import SneslSyntax
import SneslParser
import Data.Char (chr, ord)


type Env = [(Id, Val)]

eval :: Exp -> Env -> Snesl Val

eval (Var s) r = 
  case lookup s r of
    Just a -> return a
    Nothing -> error ("bad variable: " ++ s)

eval (Lit l) r = 
  return (AVal l)

eval (Tup e1 e2) r = 
  do v1 <- eval e1 r
     v2 <- eval e2 r 
     return $ TVal v1 v2

eval (Seq ss) r = 
  do vs <- mapM (\e -> eval e r) ss
     return $ SVal vs


eval (Let p e1 e2) r =
  do v1 <- eval e1 r
     eval e2 (bind p v1 ++ r)

eval (Call i es) r =
  do vs <- mapM (\e -> eval e r) es
     case lookup i r of
       Just (FVal f) -> f vs
       Nothing -> error ("bad function: " ++ i)

-- general comprehension
-- only support one variable binding
eval (GComp e0 [(x,e1)]) r =
  do vs <- (do SVal v <- eval e1 r; return v)
     vs0 <- par [eval e0 ((bind x w) ++ r)| w <- vs]
     return $ SVal vs0

--restricted comprehension
eval (RComp e0 e1) r = 
  do b <- eval e1 r 
     case b of 
        (AVal (BVal True)) -> (do v <- eval e0 r; return $ SVal [v])
        _ -> return $ SVal []




bind :: Pat -> Val -> Env
bind (PVar x) v = [(x,v)]
bind PWild v = []
bind (PTup p1 p2) (TVal v1 v2) = (bind p1 v1) ++ (bind p2 v2)


par :: [Snesl a] -> Snesl [a]
par [] = return []
par (t : ts) = 
  Snesl (case rSnesl t of
           Left (a, w1, s1) -> 
             case rSnesl (par ts) of
               Left (as, w2, s2) -> Left (a:as, w1+w2, s1 `max` s2)
               Right e -> Right e
           Right e -> Right e)



returnc :: (Int, Int) -> a -> Snesl a
returnc (w,s) a = Snesl $ Left (a, w, s)

primop :: ([AVal] -> AVal) -> Val
primop f = FVal (\as -> returnc (1,1) $ AVal (f [v | AVal v <- as]))
                           
cplus [IVal n1, IVal n2] = IVal (n1 + n2)

cminus [IVal n1, IVal n2] = IVal (n1 - n2)

cuminus [IVal n] = IVal (- n)

ctimes [IVal n1, IVal n2] = IVal (n1 * n2)

cdiv [IVal n1, IVal n2] = IVal (n1 `div` n2)

cleq [IVal n1, IVal n2] = BVal (n1 <= n2)



r0 :: Env
r0 = [("true", AVal (BVal True)),
      ("false", AVal (BVal False)),
      ("_plus", primop cplus),
      ("_minus", primop cminus),
      ("_uminus", primop cuminus),
      ("_times", primop ctimes),
      ("_div", primop cdiv),
      ("_eq", primop (\ [v1, v2] -> BVal (v1 == v2))),
      ("_leq", primop cleq),
      ("not", primop (\ [BVal b] -> BVal (not b))),

      -- iota for sequence
      ("index", FVal (\ [AVal (IVal n)] -> 
                          returnc (n,1) $ SVal [AVal (IVal i) | i <- [0..n-1]])),

      -- sequence append
      ("_append", FVal (\ [SVal v1, SVal v2] -> 
                         let v = v1 ++ v2
                         in returnc (length v,1) (SVal v))),
      -- sequence concat
      ("concat", FVal (\ [SVal vs] -> 
                           let v = concat [v | SVal v <- vs]
                           in returnc (length v,1) (SVal v))),

      -- convert tuple to sequence
      ("mkseq", FVal (\[TVal v1 v2] -> returnc (0,1) (SVal [v1, v2]))),

      -- sequence empty check, zero work 
      ("empty", FVal(\[SVal vs] -> returnc (0,1) $ AVal (BVal (null vs)))),

      -- singleton seq
      ("the", FVal (\[SVal [x]] -> returnc (0,1) x)),

       -- zip for two seqs, zero work
      ("zip", FVal (\[SVal v1, SVal v2] -> 
                 if (length v1) == (length v2)
                 then returnc (0,1) $ SVal (map (\(x,y) -> TVal x y) (zip v1 v2) )
                 else fail "zip: lengths mismatch")),
      
      -- seq partition with flags     
      ("part", FVal (\ [SVal vs, SVal flags] -> 
                            let bs = [b | AVal (BVal b) <- flags]
                                l = length vs
                            in if sum [1| b <- bs, not b] == l then
                                 returnc (l,1) $ SVal [SVal v | v <- seglist (flags2len bs) vs]
                               else fail "part: flags mismatch"))]
   
      -- reduce for sequence  
      -- scan for sequence 



-- [f,f,t,t,f,t] -> [2,0,1]
flags2len :: [Bool] -> [Int]
flags2len fs = zipWith (\x y -> x-y-1) tidx (-1:(init tidx)) 
               where tidx = [t| (t,True) <- (zip [0..(length fs)-1] fs)] 
                     len = length fs
                    

seglist :: [Int] -> [a] -> [[a]]
seglist [] [] = []
seglist (n:ns) l = take n l : seglist ns (drop n l)


doExp :: String -> IO ()
doExp s = 
    case parseString s of
        Right e ->
            case rSnesl (eval e r0) of
               Left (v, nw, ns) ->  
                  do putStrLn (show v)             
                     putStrLn ("[Work: " ++ show nw ++ ", step: " ++ show ns ++ "]")
               Right s -> putStrLn ("Runtime error: " ++ s)
        Left err -> putStrLn ("Parsing error")
