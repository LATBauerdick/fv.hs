-- file: test.hs
--
module Main ( main) where

import Data.Matrix ( Matrix, fromList, multStd2, transpose, identity )
import Fit
import Coeff (w2pt, h2p4)

hSlurp :: [Double] -> (XVec, [HVec])
hSlurp inp = (v, hl) where
  v0 :: M
  v0        = fromList 3 1 $ take 3 inp
  cv0 :: M
  cv0       = fromList 3 3 $ take 9 $ drop 3 inp
  v         = XVec (v0, cv0)
  w2pt      = inp !! 12
  nt        = round (inp !! 13) ::Int
  i0        = drop 14 inp
  lst       = (nt-1)*30
  is        = [ drop n i0 | n <-[0,30..lst]]
  hl        = [ nxtH i | i <- is ]

nxtH :: [Double] -> HVec
nxtH ii = HVec (h0, ch0) where
      (ih, ich) = splitAt 5 ii
      h0 :: M
      h0        = fromList 5 1 ih
      ch0 :: M
      ch0       = fromList 5 5 $ take 25 ich

main :: IO ()
main = let
          (v, hl) = hSlurp inp
          XVec (v0, cv0) = v
          HVec (h0, ch0) = hl !! 0
       in
  do
    print w2pt
    print v0
    print $ multStd2 (transpose v0) (multStd2 cv0 v0)
    print h0
    print $ h2p4 $ hl !! 0
    print $ multStd2 (transpose h0) (multStd2 ch0 h0)
    print [hel hv | hv <- hl]
--  print inp

inp = [
  3.355679512023926,      3.489715576171875,      7.110095977783203,
  0.2884106636047363,     0.2967556118965149,     0.4457152485847473,
  0.2967556118965149,     0.3057302236557007,     0.4589158892631531,
  0.4457152485847473,     0.4589158892631531,     0.7007381319999695,
  4.5451703E-03,
           6,
  9.0513890609145164E-04,  1.174186706542969,     0.7913663387298584,
 -5.4129425436258316E-02,  1.309153556823730,
  3.0409931517372257E-11, 3.0817798313265143E-10,-2.6150961396353978E-09,
 -6.2086684238238377E-08, 1.9006475560079394E-10, 3.0817798313265143E-10,
  3.5358195873413933E-06,-5.5664237663677341E-09,-4.7704439509743679E-08,
 -3.5389247932471335E-04,-2.6150961396353978E-09,-5.5664237663677341E-09,
  3.9334932466772443E-07, 9.2603177108685486E-06,-4.2692363422247581E-07,
 -6.2086684238238377E-08,-4.7704439509743679E-08, 9.2603177108685486E-06,
  2.7857377426698804E-04,-1.2511900422396138E-05, 1.9006475560079394E-10,
 -3.5389247932471335E-04,-4.2692363422247581E-07,-1.2511900422396138E-05,
  4.6403184533119202E-02,
 -3.2948562875390053E-04, -1.287435531616211,      3.964143753051758,
 -5.5920504033565521E-02,  2.172087669372559,
  1.0773015292342425E-11, 1.0870629917059116E-11,-9.4798713323740458E-10,
 -2.6224558524745589E-08, 5.1304871462320989E-10, 1.0870629917059116E-11,
  1.3991236755828140E-06, 6.1739335865951261E-11, 3.9363889925425610E-09,
 -1.3362320896703750E-04,-9.4798713323740458E-10, 6.1739335865951261E-11,
  1.0642112613368226E-07, 3.0040880574233597E-06,-5.7571856615368233E-08,
 -2.6224558524745589E-08, 3.9363889925425610E-09, 3.0040880574233597E-06,
  1.0815335554070771E-04,-1.6780244322944782E-06, 5.1304871462320989E-10,
 -1.3362320896703750E-04,-5.7571856615368233E-08,-1.6780244322944782E-06,
  1.5890464186668396E-02,
  8.6099491454660892E-04,  1.190025329589844,     0.7718949913978577,
  -1.004449844360352,      4.974927902221680,
  7.8076378695612902E-10,-2.4755367200590683E-10,-1.0359136126680824E-07,
 -6.7278465394338127E-06, 4.4596313841793744E-07,-2.4755367200590683E-10,
  6.6328821048955433E-06, 2.8732655366070503E-08, 1.5816522136447020E-06,
 -8.9828821364790201E-04,-1.0359136126680824E-07, 2.8732655366070503E-08,
  1.3829509043716826E-05, 9.0345303760841489E-04,-5.9563441027421504E-05,
 -6.7278465394338127E-06, 1.5816522136447020E-06, 9.0345303760841489E-04,
  5.9390719980001450E-02,-3.8860931526869535E-03, 4.4596313841793744E-07,
 -8.9828821364790201E-04,-5.9563441027421504E-05,-3.8860931526869535E-03,
  0.1251238286495209,
 -1.7263018526136875E-03,  1.039703369140625,     0.8659646511077881,
  0.2599024176597595,      2.128120422363281,
  1.5148657328545312E-10,-7.3402152411805588E-11,-1.4714315987873761E-08,
 -6.3192055677063763E-07,-3.4522088299127063E-08,-7.3402152411805588E-11,
  1.5436929743373184E-06,-5.5447091362736955E-10,-8.1613094948806975E-08,
 -1.5131152758840472E-04,-1.4714315987873761E-08,-5.5447091362736955E-10,
  1.5367089645224041E-06, 6.8635607021860778E-05, 4.2090109673154075E-06,
 -6.3192055677063763E-07,-8.1613094948806975E-08, 6.8635607021860778E-05,
  3.2065853010863066E-03, 1.9913408323191106E-04,-3.4522088299127063E-08,
 -1.5131152758840472E-04, 4.2090109673154075E-06, 1.9913408323191106E-04,
  1.7373077571392059E-02,
  1.2108741793781519E-03,  1.282915115356445,     0.8532057404518127,
  8.5045360028743744E-03,  1.965600013732910,
  3.6512477069594595E-11, 8.9357354848829118E-10,-3.3482463468459400E-09,
 -8.1875484170268464E-08, 9.6036401053822829E-10, 8.9357354848829118E-10,
  3.0787202831561444E-06,-2.2171841251861224E-08,-2.7003440550288360E-07,
 -1.5695679758209735E-04,-3.3482463468459400E-09,-2.2171841251861224E-08,
  5.5774097518224153E-07, 1.3075616152491421E-05,-4.9851792027766351E-07,
 -8.1875484170268464E-08,-2.7003440550288360E-07, 1.3075616152491421E-05,
  3.5224124439992011E-04,-1.4417236343433615E-05, 9.6036401053822829E-10,
 -1.5695679758209735E-04,-4.9851792027766351E-07,-1.4417236343433615E-05,
  1.7541546374559402E-02,
 -7.3608336970210075E-04,  1.297574043273926,     0.8316786885261536,
  -1.011060714721680,     -2.867138862609863,
  2.0176718074083055E-09, 9.1418789205377493E-10,-2.5551665316925209E-07,
 -1.5318933947128244E-05,-3.4175937457803229E-07, 9.1418789205377493E-10,
  7.4829795266850851E-06,-1.1038221003900617E-07,-6.1672653828281909E-06,
 -9.3757675494998693E-04,-2.5551665316925209E-07,-1.1038221003900617E-07,
  3.2483072573086247E-05, 1.9545238465070724E-03, 4.3123862269567326E-05,
 -1.5318933947128244E-05,-6.1672653828281909E-06, 1.9545238465070724E-03,
  0.1181144416332245,     2.5763250887393951E-03,-3.4175937457803229E-07,
 -9.3757675494998693E-04, 4.3123862269567326E-05, 2.5763250887393951E-03,
  0.1227073818445206
      ]
