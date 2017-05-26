{- A minimum Streaming NESL interpreter -}

module SneslInterp where

import SneslSyntax
import SneslParser
import Data.Char (chr, ord)
import Data.List (transpose)


runSneslInterpDefs :: [Def] -> SEnv -> Either String SEnv
runSneslInterpDefs [] e = Right e 
runSneslInterpDefs (d:ds) e0 = 
    case rSnesl (sneslInterpDef d) e0 of 
        Right (e1, _, _) -> 
            case  runSneslInterpDefs ds (e1++e0) of 
              Right es -> Right es 
              Left err -> Left $ "SNESL interpreting error: " ++ err
        Left err' -> Left $ "SNESL interpreting error: " ++ err'


sneslInterpDef :: Def -> Snesl SEnv
sneslInterpDef (FDef fname args _ e) = 
  do let ids = fst $ unzip args 
         f vs = localSEnv (zip ids vs ++ e1) $ eval e
         e1 = [(fname, FVal f)]
     return e1


--sneslInterpDef (EDef i e) r = 
--  case rSnesl (eval e r) of
--    Right (v, nw, ns) ->  return ((i,v):r)
--    Left s -> fail $ "Snesl runtime error: "++s


runSneslExp :: Exp -> SEnv -> Either String (Val,Int,Int)
runSneslExp e env = 
  case rSnesl (eval e) env of
    Right (v, nw, ns) ->  Right (v,nw,ns) 
    Left s -> Left $ "SNESL interpreting error: " ++ s


lookupVar :: Id -> Snesl Val 
lookupVar i = 
  do env <- askSEnv 
     case lookup i env of
        Just a -> return a
        Nothing -> fail $ "bad variable: " ++ i


askSEnv :: Snesl SEnv
askSEnv = Snesl $ \ env -> Right (env, 0,0) 


localSEnv :: SEnv -> Snesl a -> Snesl a 
localSEnv env m = Snesl $ \ env0 -> rSnesl m (env++env0) 



eval :: Exp -> Snesl Val

eval (Var i) = lookupVar i 

eval (Lit l) = 
  returnc (1,1) (AVal l)

eval (Tup e1 e2) = 
  do v1 <- eval e1
     v2 <- eval e2 
     return $ TVal v1 v2

eval (SeqNil tp) =
     returnc (1,1) $ SVal []

eval (Seq es) = 
  do vs <- mapM (\e -> eval e) es  
     returnc (wrapWork(length vs),1) $ SVal vs

eval (Let p e1 e2) =
  do v1 <- eval e1
     localSEnv (bind p v1) $ eval e2 

eval (Call i es) =
  do vs <- mapM (\e -> eval e) es
     env <- askSEnv
     case lookup i env of
       Just (FVal f) -> f vs
       Just _ -> fail $ "function and variable names are identical: " ++ i
       Nothing -> fail $ "bad function: " ++ i


-- general comprehension
eval (GComp e0 ps) =
  do vs <- mapM (\(_,e) -> eval e) ps 
     let vs'' = [v | SVal v <- vs] 
         vs' = transpose vs''
         v0l = length $ head vs''  
     if all (\v -> length v == v0l) vs''
     then (do 
             let binds = zipWith (\pl vl -> 
                                 concat $ zipWith (\(p,_) v -> bind p v) pl vl)
                               (replicate (length vs') ps) vs' 
             vss <- par $ zipWith (\e b -> localSEnv b $ eval e) 
                                  (replicate (length vs') e0) binds
             returnc (1,1) $ SVal vss)
     else fail "length mismatch in comprehension"
     

--restricted comprehension
eval (RComp e0 e1) = 
  do (AVal (BVal b)) <- eval e1
     case b of 
        True -> (do v <- eval e0; returnc (1,1) (SVal [v]))
        _ -> returnc (1,1) $ SVal []



bind :: Pat -> Val -> SEnv
bind (PVar x) v = [(x,v)]
bind PWild v = []
bind (PTup p1 p2) (TVal v1 v2) = (bind p1 v1) ++ (bind p2 v2)


par :: [Snesl a] -> Snesl [a]
par [] = return []
par (t : ts) = Snesl $ \ env -> 
    case rSnesl t env of
       Right (a, w1, s1) -> 
         case rSnesl (par ts) env of
           Right (as, w2, s2) -> Right (a:as, w1+w2, s1 `max` s2)
           Left e -> Left e
       Left e' -> Left e'



returnc :: (Int, Int) -> a -> Snesl a
returnc (w,s) a = Snesl $ \ _  -> Right (a, w, s)


-- For the operation that can consume(and produce) empty sequences
wrapWork :: Int -> Int 
wrapWork i = i + 1 


primop :: ([AVal] -> AVal) -> Val
primop f = FVal (\as -> returnc (1,1) $ AVal (f [v | AVal v <- as]))
                           
cplus [IVal n1, IVal n2] = IVal (n1 + n2)

cminus [IVal n1, IVal n2] = IVal (n1 - n2)

cuminus [IVal n] = IVal (- n)

ctimes [IVal n1, IVal n2] = IVal (n1 * n2)

cdiv [IVal n1, IVal n2] = IVal (n1 `div` n2)

cleq [IVal n1, IVal n2] = BVal (n1 <= n2)



se0 :: SEnv
se0 = [("_plus", primop cplus),
      ("_minus", primop cminus),
      ("_uminus", primop cuminus),
      ("_times", primop ctimes),
      ("_div", primop cdiv),
      ("_eq", primop (\ [v1, v2] -> BVal (v1 == v2))),
      ("_leq", primop cleq),
      ("not", primop (\ [BVal b] -> BVal (not b))),

      -- iota for sequence
      ("index", FVal (\ [AVal (IVal n)] ->
                          returnc (wrapWork n, 1) $ SVal [AVal (IVal i) | i <- [0..n-1]])),

      -- sequence append
      ("_append", FVal (\ [SVal v1, SVal v2] -> 
                         let v = v1 ++ v2 
                         in returnc (wrapWork $ length v, 1) (SVal v))),
      -- sequence concat
      ("concat", FVal (\ [SVal vs] -> 
                           let v = concat [v | SVal v <- vs]
                           in returnc (wrapWork $ length v,1) (SVal v))),

       -- singleton seq
      ("the", FVal (\[SVal x ] -> 
          if (length x == 1) 
          then returnc (wrapWork 1, 1) $ head x
          else fail "the: length mismatch")),

      -- sequence empty check, zero work 
      ("empty", FVal(\[SVal vs] -> returnc (wrapWork 0,1) $ AVal (BVal (null vs)))),
     

      -- seq partition with flags     
      ("part", FVal (\ [SVal vs, SVal flags] -> 
                            let bs = [b | AVal (BVal b) <- flags]
                                l = length vs
                            in if sum [1| b <- bs, not b] == l then
                                 returnc (wrapWork l,1) $ SVal [SVal v | v <- seglist (flags2len bs) vs]
                               else fail "part: flags mismatch")),


      ("scanExPlus", FVal (\ [SVal vs] -> 
           let is = [i | AVal (IVal i) <- vs]
               l = length is 
               rs = init $ scanl (+) 0 is  
            in returnc (wrapWork l, 1) 
                      $ SVal [AVal (IVal i) | i <-rs])), 

      ("reducePlus", FVal (\ [SVal vs] -> 
           let is = [i | AVal (IVal i) <- vs]
               l = length is 
            in returnc (wrapWork l, 1) $ AVal $ IVal (sum is) ))]
   


-- [f,f,t,t,f,t] -> [2,0,1]
flags2len :: [Bool] -> [Int]
flags2len fs = zipWith (\x y -> x-y-1) tidx (-1:(init tidx)) 
               where tidx = [t| (t,True) <- (zip [0..(length fs)-1] fs)] 
                     len = length fs
                    
-- [3,2] -> [FFT FT] => [[FFT],[FT]] -- i.e. partition
seglist :: [Int] -> [a] -> [[a]]
seglist [] [] = []
seglist (n:ns) l = take n l : seglist ns (drop n l)

