import SneslInterp
import SneslParser
import SvcodeInterp
import SneslCompiler
import SvcodeSyntax
import SneslSyntax
import SneslTyping
import DataTrans

import System.Environment


main = do args <- getArgs
          case args of
            [file] -> runFile file 
            _ -> putStrLn "Input file error."


runFile :: FilePath -> IO () 
runFile file =
   do prog <- readFile file 
      testExample' prog

-- disregard the expression evaluation values
testExample' :: String -> IO()
testExample' prog =  
    case runProg prog of 
        Left err -> putStrLn err 
        Right ((_,w,s),tp, b, (_,w',s')) 
           -> if b then 
                     do putStrLn $ "SNESL [work: " ++ show w ++ ", step: "
                                      ++ show s ++ "]"
                        putStrLn $ "SVCODE [work: " ++ show w' ++ ", step: " 
                                      ++ show s' ++ "]"
                   else 
                     do putStrLn $ "Error: SNESL and SVCODE results are different!"



testExample :: String -> IO()
testExample prog =  
    case runProg prog of 
        Left err -> putStrLn err 
        Right ((v,w,s),tp, b, (sv,w',s')) 
           -> if b then 
                     do putStrLn $ show v ++ " :: " ++ show tp 
                        putStrLn $ "SNESL [work: " ++ show w ++ ", step: "
                                      ++ show s ++ "]"
                        putStrLn $ "SVCODE [work: " ++ show w' ++ ", step: " 
                                      ++ show s' ++ "]"
                   else 
                     do putStrLn $ "Error: SNESL and SVCODE results are different!"
                        putStrLn $ "SNESL: " ++ show v 
                        putStrLn $ "SVCODE: " ++ show sv


-- formatted return value
runProg :: String ->  Either String ((Val,Int,Int),Type,Bool,(Val,Int,Int)) 
runProg p = 
    do absProg <- parseString p    -- parse the SNESL expression
       sneslTy <- typing absProg    -- get the expression's type
       (sneslRes,w,s) <- runSneslInterp absProg  -- SNESL interpreting result
       svcode <- compiler absProg     -- SVCODE generated from the SNESL expression
       (svcodeRes,(w',s')) <- runSvcodeProg svcode    -- SVCODE interpreting result
       let svcodeRes' = dataTransBack sneslTy $ recPair2seq sneslTy svcodeRes
           compRes = compareVal sneslRes svcodeRes'  -- compare the two results       
       return ((sneslRes,w,s),sneslTy, compRes, (svcodeRes', w',s'))


-- not formatted return value
runProg' p = 
    do absProg <- parseString p    -- parse the SNESL expression
       sneslTy <- typing absProg    -- get the expression's type
       (sneslRes,w,s) <- runSneslInterp absProg  -- SNESL interpreting result
       svcode <- compiler absProg     -- SVCODE generated from the SNESL expression
       (svcodeRes,(w',s')) <- runSvcodeProg svcode    -- SVCODE interpreting result
       return (sneslRes, sneslTy,svcode,svcodeRes)
       --let svcodeRes' = dataTransBack sneslTy $ recPair2seq sneslTy svcodeRes
           --compRes = compareVal sneslRes svcodeRes'  -- compare the two results       
       --return ((sneslRes,w,s),sneslTy, (svcodeRes', w',s'))


-- helper functions for comparing a SNESL value and a SVCODE value
          
-- compare two SNESL values
compareVal :: Val -> Val -> Bool
compareVal (AVal (IVal i1)) (AVal (IVal i2)) = i1 == i2
compareVal (AVal (BVal b1)) (AVal (BVal b2)) = b1 == b2
compareVal (TVal v1 v2) (TVal v1' v2') = (compareVal v1 v1') && (compareVal v2 v2')
compareVal (SVal vs1) (SVal vs2) = 
    if length vs1 == length vs2 
    then all (\x -> x) $ zipWith compareVal vs1 vs2
    else False
compareVal _ _ = False 


-- recursively change SPVal back to SSVal if the SVCODE value 
-- is a sequence not a pair according to its high-level type
recPair2seq :: Type -> SvVal -> SvVal
recPair2seq TInt s = s 
recPair2seq TBool s = s 
recPair2seq (TSeq t) (SPVal v1 (SBVal v2)) = SSVal v1' v2
    where v1' = recPair2seq t v1 
recPair2seq (TTup t1 t2) (SPVal v1 v2) = SPVal v1' v2' 
    where v1' = recPair2seq t1 v1 
          v2' = recPair2seq t2 v2


-- some examples

manyTest ps = 
  let res = map runProg ps
  in  [ b | Right (_, _, b, _) <- res ]


progs = [prog1,prog2,prog3,prog4,prog5,prog6,prog7,prog8,prog9, prog10]
                          

-- An example program: compute all the primes less than the number 'count'
prog1 = "let count = 50; " ++
        "    rs1 = {{{x+1 | a / (x+1) * (x+1) == a} : x in &a}: a in &count} ;"  ++
         "   rs2 = {reducePlus(concat(z)): z in rs1} "  ++
        "in  concat({{x | x+1 == y}: x in &count, y in rs2})"


-- An example for '_append', a = {{{0, 1}}, {{3}}} , b = {{{4}},    {{5, 9}}}
prog2 = "let a = {{&2|T}|T} ++ {{{3|T}|T} |T} ; "++  
        "    b = {{{4|T}|T}|T} ++ {{{5|T} ++ {9|T}|T}|T} " ++ 
        " in {x ++ y : x in a, y in b}"

-- same as prog2, using primitive sequences instead of guards
prog3 = "let a = {{&2}} ++ {{{3}}} ; "++  
        "    b = {{{4}}} ++ {{{5} ++ {9}}} " ++ 
        " in {a ++ b : _ in &2}"

-- more bug-fixed  programs

prog4 = "let n = 10 in {{x: _ in &n} : x in &n}" -- #8

prog5 = "{concat({}:{int}) : _ in &2}" -- #5

prog6 = "let x = &5 in let x = {x: _ in &2} in x "

prog7 = "let x = ({&2|T}, {3|T}) in x"

prog8 = "let x = {(1,2) : _ in &2} in {{x|T} : _ in &3}"

prog9 = "let x = &2 in {{x: _ in &a} : a in &3}"

prog10 = "{}:{int}++{{1}}"

-- Wrong example; shoulg throw an Excpetion
prog11 = "let x = 5; (y,z) = x in 5"  
