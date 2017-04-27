-- compute all the primes less than 'count'
let count = arg?; 
    rs1 = {{{x+1 | a / (x+1) * (x+1) == a} : x in &a}: a in &count} ;
    rs2 = {reducePlus(concat(z)): z in rs1} 
 in  concat({{x | x+1 == y}: x in &count, y in rs2})