{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE ExplicitForAll #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE RankNTypes #-}
--{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE NamedFieldPuns #-}

module Data.Cov
    where

import Prelude
import qualified Data.Vector.Unboxed as A
  ( Vector, length, fromList, toList, unsafeIndex, create, foldl, zipWith )
import qualified Data.Vector.Unboxed.Mutable as MA
  ( new, unsafeWrite )
import Control.Loop ( numLoop )
-- import Data.Array as A
--   ( replicate, unsafeIndex, zipWith, length, foldl, range, take
--   )
-- import Control.Monad.Eff ( forE )
--                      , pushAllSTArray, unsafeFreeze)
import Data.Foldable ( sum )
-- import Partial.Unsafe ( unsafePartial )
import Data.Maybe ( Maybe (..) )
import Control.MonadZero (guard)
-- import Data.Int ( toNumber, ceil )
-- import Math ( abs, sqrt )
-- import Unsafe.Coerce  as Unsafe.Coerce ( unsafeCoerce )

import qualified Data.SimpleMatrix as M
  ( Matrix
  , transpose
  , fromArray, fromArray2, toArray
  )

--------------------------------------------------------------
-- adapting for PureScript

type Number = Double
type Array a = A.Vector a
uidx :: A.Vector a -> Int -> a
uidx = A.unsafeIndex

--------------------------------------------------------------

newtype Dim3 = DDim3 Int
newtype Dim4 = DDim4 Int
newtype Dim5 = DDim5 Int
class DDim a where
  ddim :: a -> Int
instance DDim Dim3 where
  ddim _ = 3
instance DDim Dim4 where
  ddim _ = 4
instance DDim Dim5 where
  ddim _ = 5
instance DDim a where
  ddim _ = undefined

class Dim a where
  dim :: a -> Int
instance Dim (Cov a) where
  dim ccc = n where
    xx = undefined::a
    n = ddim xx
instance Dim (Cov Dim3) where
  dim ccc = 3
instance Dim (Cov Dim4) where
  dim ccc = 4
instance Dim (Cov Dim5) where
  dim ccc = 5

newtype Cov a   = Cov { vc :: Array Number }
newtype Jac a b = Jac { vj :: Array Number }
newtype Vec a   = Vec { vv :: Array Number }
type Cov3 = Cov Dim3
type Cov4 = Cov Dim4
type Cov5 = Cov Dim5
{-- type Jac43 = Jac Dim4 Dim3 --}
type Jac53 = Jac Dim5 Dim3
type Jac33 = Jac Dim3 Dim3
type Jac34 = Jac Dim3 Dim4
type Jac35 = Jac Dim3 Dim5
type Jac44 = Jac Dim4 Dim4
type Jac55 = Jac Dim5 Dim5
type Vec3 = Vec Dim3
type Vec4 = Vec Dim4
type Vec5 = Vec Dim5
data Jacs = Jacs {aa :: Jac53, bb :: Jac53, h0 :: Vec5}

-- access to arrays of symmetrical matrices
uGet :: Array Number -> Int -> Int -> Int -> Number
uGet a w i j | i <= j     = uidx a ((i-1)*w - (i-1)*(i-2)/2 + j-i)
             | otherwise = uidx a ((j-1)*w - (j-1)*(j-2)/2 + i-j)
indV :: Int -> Int -> Int -> Int
indV w i0 j0 = (i0*w+j0)
indVs :: Int -> Int -> Int -> Int
indVs w i0 j0 | i0 <= j0  = (i0*w - i0*(i0-1) `div` 2 + j0-i0)
              | otherwise = (j0*w - j0*(j0-1) `div` 2 + i0-j0)

-------------------------------------------------------------------------
-------------------------------------------------------------------------
-------------------------------------------------------------------------
-------------------------------------------------------------------------
-- Mat to give behavior to Cov and Vec and Jac
-- ability to convert to and from Matrix and Array
-- while keeping info about dimensionality
-- also define Semiring and Ring functions
--

class Mat a where
  val :: a -> Array Number
  fromArray :: Array Number -> a
  toArray :: a -> Array Number
instance Mat (Cov a) where
  val (Cov {vc}) = vc
  fromArray a = c' where
    l = A.length a
    c' = case l of
      6   -> Cov {vc= a}
      10  -> Cov {vc= a}
      15  -> Cov {vc= a}
      _   -> Cov {vc= let
          n = floor . sqrt . fromIntegral $ l
          iv = indV n
        in A.fromList $ do -- only upper triangle
          i0 <- [0 .. (n-1)]
          j0 <- [i0 .. (n-1)]
          pure $ uidx a (iv i0 j0) }

  toArray c@(Cov {vc=v}) = v' where
    l = A.length v
    n = case l of
      6  -> 3
      10 -> 4
      15 -> 5
    iv = indVs n
    v' = A.fromList $ do
      i0 <- [0..(n-1)]
      j0 <- [0..(n-1)]
      pure $ uidx v (iv i0 j0)
instance Mat (Vec a) where
  val (Vec {vv}) = vv
  fromArray a = Vec {vv= a}
  toArray (Vec {vv}) = vv
instance Mat (Jac a b) where
  val (Jac {vj}) = vj
  fromArray a = Jac {vj= a}
  toArray (Jac {vj}) = vj

class Mat1 a where
  toMatrix :: a -> M.Matrix
instance Mat1 (Cov a) where
  toMatrix a@(Cov {vc=v}) = case A.length v of
                            6  -> M.fromArray2 3 3 v
                            10 -> M.fromArray2 4 4 v
                            15 -> M.fromArray2 5 5 v
                            _ -> error $ "mat1Cova toMatrix "
                                          ++ show (A.length v)
instance Mat1 (Vec a) where
  toMatrix (Vec {vv=v}) = M.fromArray (A.length v) v
instance Mat1 (Jac a b) where
  toMatrix j@(Jac {vj=v}) = case A.length v of
                              9  -> M.fromArray2 3 3 v
                              16 -> M.fromArray2 4 4 v
                              25 -> M.fromArray2 5 5 v
                              12 -> M.fromArray2 3 4 v `debug` "this should not have happened ??????????????????? 4 3"
                              15 -> M.fromArray2 5 3 v `debug` "this should not have happened ??????????????????? 5 3"
                              _  -> error $ "mat1Jacaa toMatrix "
                                          ++ show (A.length v)

instance Mat1 (Jac Dim5 Dim3) where
  toMatrix (Jac {vj=v}) = M.fromArray2 5 3 v -- `debug` "WTF??? 5 3"
instance Mat1 (Jac Dim3 Dim5) where
  toMatrix (Jac {vj=v}) = M.fromArray2 3 5 v -- `debug` "WTF??? 3 5"
--{{{
--}}}
-----------------------------------------------------------------
-- | funcitons for symetric matrices: Cov
-- | type class SymMat
class SymMat a where
  inv :: Cov a -> Cov a                -- | inverse matrix
  invMaybe :: Cov a -> Maybe (Cov a)   -- | Maybe inverse matrix
  det :: Cov a -> Number               -- | determinant
  diag :: Cov a -> Array Number        -- | Array of diagonal elements
  chol :: Cov a -> Jac a a             -- | Cholsky decomposition
instance SymMat Dim3 where
  inv m = uJust (invMaybe m)
  invMaybe (Cov {vc=v}) = _inv $ A.toList v where
    _inv [a11,a12,a13,a22,a23,a33] = do
      let det = (a33*a12*a12 - 2.0*a13*a23*a12 + a13*a13*a22
                +a11*(a23*a23 - a22*a33))
      guard $ (abs det) > 1.0e-50
      let
          b11 = (a23*a23 - a22*a33)/det
          b12 = (a12*a33 - a13*a23)/det
          b13 = (a13*a22 - a12*a23)/det
          b22 = (a13*a13 - a11*a33)/det
          b23 = (a11*a23 - a12*a13)/det
          b33 = (a12*a12 - a11*a22)/det
      pure $ fromArray [b11,b12,b13,b22,b23,b33]
  chol a = choldc a 3
  det (Cov {vc}) = dd where
        a = unsafePartial $ A.unsafeIndex v 0
        b = unsafePartial $ A.unsafeIndex v 1
        c = unsafePartial $ A.unsafeIndex v 2
        d = unsafePartial $ A.unsafeIndex v 3
        e = unsafePartial $ A.unsafeIndex v 4
        f = unsafePartial $ A.unsafeIndex v 5
        dd = a*d*f - a*e*e - b*b*f + 2.0*b*c*e - c*c*d
  diag (Cov {vc}) = a where
    a11 = unsafePartial $ A.unsafeIndex v 0
    a22 = unsafePartial $ A.unsafeIndex v 3
    a33 = unsafePartial $ A.unsafeIndex v 5
    a = [a11,a22,a33]
instance SymMat Dim4 where
  inv m = uJust (invMaybe m)
  invMaybe (Cov {vc=v}) = _inv $ A.toList v where
    _inv [a,b,c,d,e,f,g,h,i,j] = do
      let det = (a*e*h*j - a*e*i*i - a*f*f*j + 2.0*a*f*g*i - a*g*g*h
            - b*b*h*j + b*b*i*i - 2.0*d*(b*f*i - b*g*h - c*e*i + c*f*g)
            + b*c*(2.0*f*j - 2.0*g*i) + c*c*(g*g - e*j) + d*d*(f*f - e*h))
      guard $ (abs det) > 1.0e-50
      let a' = (-j*f*f + 2.0*g*i*f - e*i*i - g*g*h + e*h*j)/det
          b' = (b*i*i - d*f*i - c*g*i + d*g*h + c*f*j - b*h*j)/det
          c' = (c*g*g - d*f*g - b*i*g + d*e*i - c*e*j + b*f*j)/det
          d' = (d*f*f - c*g*f - b*i*f - d*e*h + b*g*h + c*e*i)/det
          e' = (-j*c*c + 2.0*d*i*c - a*i*i - d*d*h + a*h*j)/det
          f' = (f*d*d - c*g*d - b*i*d + a*g*i + b*c*j - a*f*j)/det
          g' = (g*c*c - d*f*c - b*i*c + b*d*h - a*g*h + a*f*i)/det
          h' = (-j*b*b + 2.0*d*g*b - a*g*g - d*d*e + a*e*j)/det
          i' = (i*b*b - d*f*b - c*g*b + c*d*e + a*f*g - a*e*i)/det
          j' = (-h*b*b + 2.0*c*f*b - a*f*f - c*c*e + a*e*h)/det
      pure $ fromArray [a',b',c',d',e',f',g',h',i',j']
  det (Cov {vc}) = _det v where
    _det [a,b,c,d,e,f,g,h,i,j] =
        (a*e*h*j - a*e*i*i - a*f*f*j + 2.0*a*f*g*i - a*g*g*h
          - b*b*h*j + b*b*i*i - 2.0*d*(b*f*i - b*g*h - c*e*i + c*f*g)
          + b*c*(2.0*f*j - 2.0*g*i) + c*c*(g*g - e*j) + d*d*(f*f - e*h))
    _det _ = undefined
  diag (Cov {vc=v}) = _diag $ A.toList v where
    _diag [a11,_,_,_,a22,_,_,a33,_,a44] = [a11,a22,a33,a44]
  chol a = choldc a 4
instance SymMat Dim5 where
  inv m = cholInv m 5
  invMaybe m = Just (cholInv m 5)
  det (Cov {vc}) = _det $ A.toList v where
    _det [a,b,c,d,e,f,g,h,i,j,k,l,m,n,o] =
      a*f*j*m*o - a*f*j*n*n - a*f*k*k*o + 2.0*a*f*k*l*n - a*f*l*l*m
      - a*g*g*m*o + a*g*g*n*n + 2.0*a*g*h*k*o - 2.0*a*g*h*l*n - 2.0*a*g*i*k*n
      + 2.0*a*g*i*l*m - a*h*h*j*o + a*h*h*l*l + 2.0*a*h*i*j*n - 2.0*a*h*i*k*l
      - a*i*i*j*m + a*i*i*k*k - b*b*j*m*o + b*b*j*n*n + b*b*k*k*o
      - 2.0*b*b*k*l*n + b*b*l*l*m + 2.0*b*c*g*m*o - 2.0*b*c*g*n*n - 2.0*b*c*h*k*o
      + 2.0*b*c*h*l*n + 2.0*b*c*i*k*n - 2.0*b*c*i*l*m - 2.0*b*d*g*k*o
      + 2.0*b*d*g*l*n + 2.0*b*d*h*j*o - 2.0*b*d*h*l*l - 2.0*b*d*i*j*n
      + 2.0*b*d*i*k*l + 2.0*b*e*g*k*n - 2.0*b*e*g*l*m - 2.0*b*e*h*j*n
      + 2.0*b*e*h*k*l + 2.0*b*e*i*j*m - 2.0*b*e*i*k*k - c*c*f*m*o + c*c*f*n*n
      + c*c*h*h*o - 2.0*c*c*h*i*n + c*c*i*i*m + 2.0*c*d*f*k*o - 2.0*c*d*f*l*n
      - 2.0*c*d*g*h*o + 2.0*c*d*g*i*n + 2.0*c*d*h*i*l - 2.0*c*d*i*i*k
      - 2.0*c*e*f*k*n + 2.0*c*e*f*l*m + 2.0*c*e*g*h*n - 2.0*c*e*g*i*m
      - 2.0*c*e*h*h*l + 2.0*c*e*h*i*k - d*d*f*j*o + d*d*f*l*l + d*d*g*g*o
      - 2.0*d*d*g*i*l + d*d*i*i*j + 2.0*d*e*f*j*n - 2.0*d*e*f*k*l - 2.0*d*e*g*g*n
      + 2.0*d*e*g*h*l + 2.0*d*e*g*i*k - 2.0*d*e*h*i*j - e*e*f*j*m + e*e*f*k*k
      + e*e*g*g*m - 2.0*e*e*g*h*k + e*e*h*h*j
    _det _ = undefined
  diag (Cov {vc}) = _diag $ toList vc where
    _diag [a,_,_,_,_,b,_,_,_,c,_,_,d,_,e] = [a,b,c,d,e]
  chol a = choldc a 5

class MulMat a b c | a b -> c where
  mulm :: a -> b -> c
(*.) = mulm
infixr 7 *.
instance MulMat (Cov a) (Cov a) (Jac a a) where
  mulm c1 c2 = j' where
    mc1 = toMatrix c1
    mc2 = toMatrix c2
    mj' = mc1 * mc2
    j' = fromArray $ M.toArray mj'
instance MulMat (Jac a b) (Cov b) (Jac a b) where
  mulm j@(Jac {vj= va}) c@(Cov {vc= vb}) = Jac {vj= vc} where
    nb = case A.length vb of
              6  -> 3
              10 -> 4
              15 -> 5
              _  -> error $ "mulMatJC wrong length of Cov v "
                            ++ show (A.length vb)
    na = (A.length va) `div` nb
    vc :: Array Number
    vc = A.create $ do
      v <- MA.new $ na * nb
      let ixa = indV nb
          ixb = indVs na
          ixc = indV na
      numLoop 0 (na-1) $ \i0 -> 
        numLoop 0 (nb-1) $ \j0 -> 
          MA.unsafeWrite v (ixc i0 j0) $
          sum [ (uidx va (ixa i0 k0)) * (uidx vb (ixb k0 j0)) 
                 | k0 <- [0 .. nb-1] ]
      return v
instance MulMat (Cov a) (Jac a b) (Jac a b) where
  mulm c@(Cov {vc= va}) j@(Jac {vj= vb}) = Jac {vj= v'} where
    na = case A.length va of
              6  -> 3
              10 -> 4
              15 -> 5
              _  -> error $ "mulMatCJ wrong length of Cov v "
                            ++ show (A.length va)
    nb = (A.length vb) `div` na
    vc = A.create $ do
      v <- MA.new $ na * nb
      let ixa = indVs na
          ixb = indV na
          ixc = indV na
      numLoop 0 (na-1) $ \i0 -> 
        numLoop 0 (nb-1) $ \j0 -> 
          MA.unsafeWrite v (ixc i0 j0) $
          sum [ (uidx va (ixa i0 k0)) * (uidx vb (ixb k0 j0)) 
                 | k0 <- [0 .. na-1] ]
      return v
instance MulMat (Jac a b) (Vec b) (Vec a) where
  mulm j@(Jac {vj= va}) v@(Vec {vv=vb}) = Vec {vv=vc} where
    nb = A.length vb
    na = (A.length va)/nb
    vc = A.create $ do
      v <- MA.new $ na*nb
      let ixa = indVs nb
          ixb = indV 1
          ixc = indV 1

      numLoop 0 (na-1) $ \i0 -> 
        MA.unsafeWrite v i0 $
        sum [ (uidx va (ixa i0 k0)) * (uidx vb k0 )
                 | k0 <- [0 .. nb-1] ]
      pure v
instance MulMat (Jac Dim3 Dim5) (Jac Dim5 Dim3) (Jac Dim3 Dim3) where
  mulm j1 j2 = j' where
    mj1 = toMatrix j1
    mj2 = toMatrix j2
    mj' = mj1 * mj2
    j' = fromArray $ M.toArray mj'
instance MulMat (Cov a) (Vec a) (Vec a) where
  mulm c v = v' where
    mc = toMatrix c
    mv = toMatrix v
    mv' = mc * mv
    v' = fromArray $ M.toArray mv'
instance MulMat (Vec a) (Vec a) Number where
  mulm (Vec {vv=v1}) (Vec {vv=v2}) = A.foldl (+) zero $ A.zipWith (*) v1 v2
class TrMat a b | a -> b where
  tr :: a -> b
instance TrMat (Cov a) (Cov a) where
  tr c = c
instance TrMat (Jac a b) (Jac b a) where
  tr j@(Jac {vj=v}) = Jac {vj=v'} where
    l = A.length v
    na = case l of
              9 -> 3
              15 -> 5
              16 -> 4
              25 -> 5
              _  -> error $ "trMatJ: sorry, can't do anything but 5x3 and square "
                            ++ show (A.length v)
    nb = l/na
    ixa = indV nb
    v' = A.create $ do
      v <- MA.new $ na*nb
      numLoop 0 (nb-1) $ \i0 ->
        numLoop 0 (na-1) $ \j0 ->
          MA.unsafeWrite v (ixa j0 i0)
class SW a b c | a b -> c where
  sw :: a -> b -> c
(.*.) = sw
infixl 7 .*.
instance SW (Vec a) (Cov a) Number where
  sw v c = n where
    mv = toMatrix v
    mc = toMatrix c
    mc' = M.transpose mv * mc * mv
    n = uidx (M.toArray mc') 0
instance SW (Cov a) (Cov a) (Cov a) where
  sw c1 c2 = c' where
    j' = c1 *. c2 *. c1
    c' = fromArray $ toArray j'
instance SW (Jac a b) (Cov a) (Cov b) where
  sw j@(Jac {vj= va}) c@(Cov {vc= vb}) = Cov {vc= v'} where
    l = A.length vb
    n = case l of
              6  -> 3
              10 -> 4
              15 -> 5
              _  -> error $ "swJac: don'w know how to " ++ show l
    m = (A.length va)/n -- > mxn * nxn * nxm -> mxm

    vint = A.create $ do
      v <- MA.new (n*m)
      let ixa = indVs n
      let ixb = indV m
      let ixc = indV m
      numLoop 0 (n-1) $ \i0 ->
        numLoop 0 (m-1) $ \j0 ->
          MA.unsafeWrite v (ixc i0 j0) $
            sum [ (uidx vb (ixa i0 k0)) * (uidx va (ixb k0 jo))
              | k0 <- [0 .. ( n-1)] ]
      pure v
    v' = do
      v <- MA.new n*m
      let ixa = indV m
          ixb = indV m
          ixc = indVs m
      numLoop 0 (m-1) $ \i0 ->
        numLoop i0 (m-1) $ \j0 ->
          MA.unsafeWrite v (ixc i0 j0) $
            sum [ (uidx va (ixa k0 i0 )) * (uidx vint (ixb k0 j0))
              | k0 <- [0 .. (n-1)] ]
testCov2 :: String
testCov2 = s where
  s = "Test Cov 2----------------------------------------------\n"
    ++ "Vec *. Vec = " ++ show (v3 *. v3) ++ "\n"
    ++ "Cov *. Cov = " ++ show ((one::Cov3) *. inv (one::Cov3)) ++ "\n"
    ++ "Vec + Vec = " ++ show (v5 + v5) ++ "\n"
    ++ "chol Cov = " ++ show (chol (one::Cov5)) ++ "\n"
    ++ "Vec .*. Cov = " ++ show (v5 .*. inv (one::Cov5)) ++ "\n"
  v3 = fromArray [1.0,1.0,1.0] :: Vec3
  v5 = fromArray [1.0,1.0,1.0,1.0,1.0] :: Vec5

-- instance Semiring (Cov Dim3) where
--   add (Cov {v= v1}) (Cov {v= v2}) = Cov {v= A.zipWith (+) v1 v2}
--   zero = Cov {v= A.replicate 6 0.0 }
--   mul (Cov {v= a}) (Cov {v= b}) = error "------------> mul cov3 * cov3 not allowed"
--   one = Cov { v= [1.0, 0.0, 0.0, 1.0, 0.0, 1.0] }
-- instance Ring (Cov Dim3) where
--   sub (Cov {v= v1}) (Cov {v= v2}) = Cov {v= A.zipWith (-) v1 v2}
instance Show (Cov Dim3) where
  show c = "Show (Cov Dim3) \n" ++ (show $ toMatrix c)

-- instance Semiring (Cov Dim4) where
--   add (Cov {v= v1}) (Cov {v= v2}) = Cov {v= A.zipWith (+) v1 v2}
--   zero = Cov {v= A.replicate 10 0.0 }
--   mul (Cov {v= a}) (Cov {v= b}) = error "------------> mul cov4 * cov4 not allowed"
--   one = Cov { v= [1.0,0.0,0.0,0.0,1.0,0.0,0.0,1.0,0.0,1.0] }
-- instance Ring (Cov Dim4) where
--   sub (Cov {v= v1}) (Cov {v= v2}) = Cov {v= A.zipWith (-) v1 v2}
instance Show (Cov Dim4) where
  show c = "Show (Cov Dim4)\n" ++ (show $ toMatrix c)

-- instance Semiring (Cov Dim5) where
--   add (Cov {v= v1}) (Cov {v= v2}) = Cov {v= A.zipWith (+) v1 v2}
--   zero = Cov {v= A.replicate 15 0.0 }
--   mul a b = error "------------> mul cov5 * cov5 not allowed"
--   one = Cov { v= [1.0,0.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,1.0,0.0,0.0,1.0,0.0,1.0] }
-- instance Ring (Cov Dim5) where
--   sub (Cov {v= v1}) (Cov {v= v2}) = Cov {v= A.zipWith (-) v1 v2}
instance Show (Cov Dim5) where
  show c = "Show (Cov Dim5)\n" ++ (show $ toMatrix c)

-- instance Semiring (Jac a b) where
--   add (Jac {v= v1}) (Jac {v= v2}) = Jac {v= A.zipWith (+) v1 v2}
--   zero = undefined
--   mul (Jac {v= v1}) (Jac {v= v2}) = undefined -- Cov {v= cov5StdMult v1 v2}
--   one = undefined
-- instance Ring (Jac a b) where
--   sub (Jac {v= v1}) (Jac {v= v2}) = Jac {v= A.zipWith (-) v1 v2}
instance Show (Jac a b) where
  show a = "Show Jac\n" ++ show (toMatrix a)

-- -- Instances for Vec -- these are always column vectors
-- instance Semiring (Vec Dim3) where
--   add (Vec {v= v1}) (Vec {v= v2}) = Vec {v= A.zipWith (+) v1 v2}
--   zero = Vec {v= A.replicate 3 0.0 }
--   mul (Vec {v= v1}) (Vec {v= v2}) = undefined
--   one = Vec { v= A.replicate 3 1.0 }

-- instance Semiring (Vec Dim4) where
--   add (Vec {v= v1}) (Vec {v= v2}) = Vec {v= A.zipWith (+) v1 v2}
--   zero = Vec {v= A.replicate 4 0.0 }
--   mul (Vec {v= v1}) (Vec {v= v2}) = undefined
--   one = Vec { v= A.replicate 4 1.0 }

-- instance Semiring (Vec Dim5) where
--   add (Vec {v= v1}) (Vec {v= v2}) = Vec {v= A.zipWith (+) v1 v2}
--   zero = Vec {v= A.replicate 5 0.0 }
--   mul (Vec {v= v1}) (Vec {v= v2}) = undefined
--   one = Vec { v= A.replicate 5 1.0 }

-- instance Semiring (Vec a) where
--   add (Vec {v= v1}) (Vec {v= v2}) = Vec {v= A.zipWith (+) v1 v2}
--   {-- zero = error "error calling zero for Vec a" -- Vec {v= A.replicate 5 0.0 } --}
--   zero = Vec {v= A.replicate 5 0.0 } `debug` "xxxxxxxxxxx>>> called Vec zero"
--   mul (Vec {v= v1}) (Vec {v= v2}) = undefined
--   {-- one = error "error calling one for Vec a" -- Vec { v= A.replicate 5 1.0 } --}
--   one = Vec { v= A.replicate 5 1.0 } `debug` "xxxxxxxxxxx>>> called Vec one"
-- instance Ring (Vec a) where
--   sub (Vec {v= v1}) (Vec {v= v2}) = Vec {v= A.zipWith (-) v1 v2}
instance Show (Vec a) where
  show v = "Show Vec\n" ++ show (toMatrix v)

scaleDiag :: Number -> Cov3 -> Cov3
scaleDiag s (Cov {vc=v}) = (Cov {vc= _sc $ A.toList v}) where
  _sc [a,_,_,b,_,c] = A.fromList [s*a,0.0,0.0,s*b,0.0,s*c]
  _sc _ = undefined

subm :: Int -> Vec5 -> Vec3
subm n (Vec {vv=v}) = Vec {vv= _subm $ A.toList v} where
  _subm [a,b,c,_,_] = A.fromList [a,b,c]
  _subm _ = undefined

subm2 :: Int -> Cov5 -> Cov3
subm2 n (Cov {vc=v}) = Cov {vc= _subm2 $ A.toList v} where
  _subm2 [a,b,c,_,d,e,_,_,f] = A.fromList [a,b,c,d,e,f]
  _subm2 _ = undefined


-- CHOLESKY DECOMPOSITION

-- | Simple Cholesky decomposition of a symmetric, positive definite matrix.
--   The result for a matrix /M/ is a lower triangular matrix /L/ such that:
--
--   * /M = LL^T/.
--
--   Example:
--
-- >            (  2 -1  0 )   (  1.41  0     0    )
-- >            ( -1  2 -1 )   ( -0.70  1.22  0    )
-- > choldx     (  0 -1  2 ) = (  0.00 -0.81  1.15 )
--
-- Given a positive-deﬁnite symmetric matrix a[1..n][1..n],
-- this routine constructs its Cholesky decomposition,
-- A = L · L^T
-- The Cholesky factor L is returned in the lower triangle of a,
-- except for its diagonal elements which are returned in p[1..n].


choldc :: forall a. Cov a -> Int -> Jac a a
choldc (Cov {vc= a}) n = Jac {vj= a'} where
  a' = undefined
  -- w = n
  -- ll = n*n --n*(n+1)/2
  -- idx :: Int -> Int -> Int
  -- idx i j | i <= j    = ((i-1)*w - (i-1)*(i-2)/2 + j-i)
  --         -- | otherwise = ((j-1)*w - (j-1)*(j-2)/2 + i-j)
  --         | otherwise = error "idx: i < j"
  -- idx' :: Int -> Int -> Int
  -- idx' j i | i >= j   = (i-1)*w + j-1
  --          | otherwise = error "idx': i < j"
  -- {-- run :: forall a. (forall h. Eff (st :: ST h) (STArray h a)) -> Array a --}
  -- {-- run act = pureST (act >>= unsafeFreeze) --}
  -- {-- a' = run (do --}
  -- a' = A.take (n*n) $ pureST ((do
  --   -- make a STArray of n x n + space for diagonal
  --   arr <- emptySTArray
  --   _ <- pushAllSTArray arr (A.replicate (ll+n) 0.0)

  --   -- loop over input array using Numerical Recipies algorithm (chapter 2.9)
  --   forE 1 (w+1) \i -> do
  --     forE i (w+1) \j -> do
  --         _ <- pokeSTArray arr (idx' i j) (uidx a (idx i j))
  --         let kmin = 1
  --             kmax = (i-1) + 1
  --         forE kmin kmax \k -> do
  --             aik <- peekSTArray arr (idx' k i)
  --             ajk <- peekSTArray arr (idx' k j)
  --             sum <- peekSTArray arr (idx' i j)
  --             void $ pokeSTArray arr (idx' i j) ((uJust sum)
  --                                              - (uJust aik) * (uJust ajk))

  --         msum <- peekSTArray arr (idx' i j)
  --         let sum' = uJust msum
  --             sum = if (i==j) && sum' < 0.0
  --                      then error ("choldc: not a positive definite matrix " ++ show a)
  --                      else sum'
  --         mp_i' <- peekSTArray arr (ll+i-1)
  --         let p_i' = uJust mp_i'
  --             p_i = if i == j then sqrt sum else p_i'
  --         void $ if i==j
  --                        then pokeSTArray arr (ll+i-1) p_i -- store diag terms outside main array
  --                        else pokeSTArray arr (idx' i j) (sum/p_i)
  --         pure $ unit

  --   -- copy diagonal back into array
  --   forE 1 (w+1) \i -> do
  --         maii <- peekSTArray arr (ll+i-1)
  --         let aii = uJust maii
  --         void $ pokeSTArray arr (idx' i i) aii
  --   pure arr) >>= unsafeFreeze)

-- -- | Matrix inversion using Cholesky decomposition
-- -- | based on Numerical Recipies formula in 2.9
-- --
-- cholInv :: forall a. Cov a -> Int -> Cov a
-- cholInv (Cov {vc= a}) n = Cov {vc= a'} where
  -- ll = n*n --n*(n+1)/2
  -- idx :: Int -> Int -> Int -- index into values array of symmetric matrices
  -- idx i j | i <= j    = ((i-1)*n - (i-1)*(i-2)/2 + j-i)
  --         | otherwise = ((j-1)*n - (j-1)*(j-2)/2 + i-j)
  -- idx' :: Int -> Int -> Int -- index into values array for full matrix
  -- idx' i j = (i-1)*n + j-1
  -- l = pureST ((do
  --   -- make a STArray of n x n + space for diagonal +1 for summing
  --   arr <- emptySTArray
  --   void $ pushAllSTArray arr (A.replicate (ll+n+1) 0.0)

  --   -- loop over input array using Numerical Recipies algorithm (chapter 2.9)
  --   forE 1 (n+1) \i -> do
  --     forE i (n+1) \j -> do
  --         let aij = uidx a (idx i j)
  --         void $ if i==j then pokeSTArray arr (ll+i-1) aij
  --                        else pokeSTArray arr (idx' j i) aij
  --         forE 1 i \k -> do
  --             maik <- peekSTArray arr (idx' i k)
  --             majk <- peekSTArray arr (idx' j k)
  --             maij <- if i==j then peekSTArray arr (ll+i-1)
  --                             else peekSTArray arr (idx' j i)
  --             let sum = (uJust maij) - (uJust maik) * (uJust majk)
  --             void $ if i==j then pokeSTArray arr (ll+i-1) sum
  --                            else pokeSTArray arr (idx' j i) sum
  --         msum <- if i==j then peekSTArray arr (ll+i-1)
  --                         else peekSTArray arr (idx' j i)
  --         let sum' = uJust msum
  --             sum = if i==j && sum' < 0.0
  --                      then error ("choldInv: not a positive definite matrix "
  --                                   ++ show a)
  --                      else sum'
  --         mp_i' <- peekSTArray arr (ll+i-1)
  --         let p_i' = uJust mp_i'
  --             p_i = if i == j then sqrt sum else p_i'
  --         void $ if i==j then pokeSTArray arr (ll+i-1) p_i
  --                        else pokeSTArray arr (idx' j i) (sum/p_i)
  --         pure $ unit

  --   -- invert L -> L^(-1)
  --   forE 1 (n+1) \i -> do
  --     mp_i <- peekSTArray arr (ll+i-1)
  --     void $ pokeSTArray arr (idx' i i) (1.0/(uJust mp_i))
  --     forE (i+1) (n+1) \j -> do
  --       void $ pokeSTArray arr (ll+n) 0.0
  --       forE i j \k -> do
  --         majk <- peekSTArray arr (idx' j k)
  --         maki <- peekSTArray arr (idx' k i)
  --         sum <- peekSTArray arr (ll+n)
  --         void $ pokeSTArray arr (ll+n)
  --                   ((uJust sum) - (uJust majk) * (uJust maki))
  --       msum <- peekSTArray arr (ll+n)
  --       mp_j <- peekSTArray arr (ll+j-1)
  --       void $ pokeSTArray arr (idx' j i) ((uJust msum)/(uJust mp_j))
  --   pure arr) >>= unsafeFreeze)
  -- a' = do
  --   i <- A.range 1 n
  --   j <- A.range i n
  --   let aij = sum do
  --                 k <- A.range 1 n
  --                 pure $ (uidx l (idx' k i)) * (uidx l (idx' k j))
  --   pure $ aij

--C version Numerical Recipies 2.9
--for (i=1;i<=n;i++) {
--  for (j=i;j<=n;j++) {
--    for (sum=a[i][j],k=i-1;k>=1;k--) sum -= a[i][k]*a[j][k];
--    if (i == j) {
--      if (sum <= 0.0) nrerror("choldc failed");
--      p[i]=sqrt(sum);
--    } else a[j][i]=sum/p[i];
--  }
--}
-- In this, and many other applications, one often needs L^(−1) . The lower
-- triangle of this matrix can be efﬁciently found from the output of choldc:
--for (i=1;i<=n;i++) {
--  a[i][i]=1.0/p[i];
--  for (j=i+1;j<=n;j++) {
--    sum=0.0;
--    for (k=i;k<j;k++) sum -= a[j][k]*a[k][i];
--    a[j][i]=sum/p[j];
--  }
--}
