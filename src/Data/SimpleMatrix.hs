{-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE ExplicitForAll #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE RankNTypes #-}
-- {-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Data.SimpleMatrix 
  ( Matrix (..)
  , transpose
  , fromArray, fromArray2, toArray
  ) where

import Prelude
-- import Data.Tuple ( Tuple (..) )
import qualified Data.Vector.Unboxed as A
  ( Vector
  , unsafeIndex
  , length
  , singleton
  , fromList
  , map
  , maximum
  )
import Data.Foldable ( sum )
import Data.String as S ( unlines, unwords )

--------------------------------------------------------------
-- adapting for PureScript
import Data.Monoid ( (<>) )

data Tuple a b = Tuple a b
-- type List a = [a]
type Number = Double
type Array a = A.Vector a
uidx :: A.Vector Number -> Int -> Number
uidx = A.unsafeIndex
(<<<) :: (b -> c) -> (a -> b) -> a -> c
(<<<) = (.)
infixr 9 <<<

------------------------------------------------------------------------
-- utility functions
-- access to arrays of symmetrical matrices
indV :: Int -> Int -> Int -> Int
indV w i0 j0 = (i0*w+j0)
indVs :: Int -> Int -> Int -> Int
indVs w i0 j0 | i0 <= j0  = (i0*w - i0*(i0-1) `div` 2 + j0-i0)
              | otherwise = (j0*w - j0*(j0-1) `div` 2 + i0-j0)


------------------------------------------------------------------------
-- | Dense Matrix implementation
-- | Type of matrices.
--
--   Elements can be of any type. Rows and columns
--   are indexed starting by 1. This means that, if @m : Matrix a@ and
--   @i,j :: Int@, then @m ! (i,j)@ is the element in the @i@-th row and
--   @j@-th column of @m@.
data Matrix = M_
  { nrows     :: Int
  , ncols     :: Int
  , roff      :: Int
  , coff      :: Int
  , vcols     :: Int -- ^ Number of columns of the matrix without offset
  , values    :: Array Number
  }

-- | /O(rows*cols)/. Generate a matrix from a generator function.
--   Example of usage:
--
-- >                                  (  1  0 -1 -2 )
-- >                                  (  3  2  1  0 )
-- >                                  (  5  4  3  2 )
-- > matrix 4 4 $ \(i,j) -> 2*i - j = (  7  6  5  4 )
matrix :: Int -- ^ Rows
       -> Int -- ^ Columns
       -> ((Tuple Int Int) -> Number) -- ^ Generator function
       -> Matrix
matrix n m f = M_ {nrows= n, ncols= m, roff= 0, coff= 0, vcols= m, values= val} where
--  val = undefined
  val = A.fromList $ do
    i <- [1 .. n]
    j <- [1 .. m]
    pure $ f (Tuple i j)

-- | Create a matrix from a non-empty list given the desired size.
--   The list must have at least /rows*cols/ elements.
--   An example:
--
-- >                            ( 1 2 3 )
-- >                            ( 4 5 6 )
-- > fromArray2 3 3 (1 .. 9) =  ( 7 8 9 )
--
-- | Create column vector from array
fromArray :: Int -> Array Number -> Matrix
fromArray r vs = M_ {nrows= r, ncols= 1, roff= 0, coff= 0, vcols= 1, values= vs}
-- | Create matrix from array
fromArray2 :: Int -> Int -> Array Number -> Matrix
fromArray2 r c vs | (A.length vs) == r*c
                    = M_ {nrows= r, ncols= c
                        , roff= 0, coff= 0 , vcols= c , values= vs}
                  | r==c && (A.length vs) == r*(r+1) `div` 2
                    = let
                          n = r
                          ixc = indVs n
                          vs' = A.fromList $ do
                            i0 <- [0 .. n-1]
                            j0 <- [0 .. n-1]
                            pure $ uidx vs (ixc i0 j0)
                      in M_ {nrows= n, ncols= n, roff= 0, coff= 0, vcols= n, values= vs'}
                  | otherwise = error $ "---- fromArray2 invalid array length "
                                <> show (A.length vs)
-- | Just a cool way to output the size of a matrix.
sizeStr :: Int -> Int -> String
sizeStr n m = show n ++ "x" ++ show m
-- | Display a matrix as a 'String' using the 'Show' instance of its elements.
--instance Show Matrix where show _ = "Show Matrix ... "
instance Show Matrix where
  show m@(M_ {nrows= r, ncols= c, values= v}) = S.unlines ls where
    ls = do
      i <- [1 .. r]
      let ws :: [String]
          ws = map (\j -> fillBlanks mx (show $ unsafeGet i j m)) [1 .. c]
      pure $ "( " <> S.unwords ws <> " )"
    mx = A.maximum $ A.map (length <<< show) v
    -- mx = fromMaybe 0 (maximum $ map (length <<< show) v)
    fillBlanks k str =
       (replicate (k - length str) ' ') <> str

-- | Get the elements of a matrix stored in an Array.
--
-- >         ( 1 2 3 )
-- >         ( 4 5 6 )
-- > toArray ( 7 8 9 ) = [1,2,3,4,5,6,7,8,9]

toArray :: Matrix -> Array Number
toArray m@(M_ {nrows= r, ncols= c}) = A.fromList $ do
  i <- [1 .. r]
  j <- [1 .. c]
  pure $ unsafeGet i j m


-- | /O(1)/. Unsafe variant of 'getElem', without bounds checking.
unsafeGet :: Int      -- ^ Row
             -> Int      -- ^ Column
             -> Matrix   -- ^ Matrix
             -> Number
unsafeGet i j (M_ {roff= ro, coff= co, vcols= w, values= v}) = A.unsafeIndex v $ encode w (i+ro) (j+co)

encode :: Int -> Int -> Int -> Int
encode m i j = (i-1)*m + j - 1

-- | /O(rows*cols)/. The transpose of a matrix.
--   Example:
--
-- >           ( 1 2 3 )   ( 1 4 7 )
-- >           ( 4 5 6 )   ( 2 5 8 )
-- > transpose ( 7 8 9 ) = ( 3 6 9 )
transpose :: Matrix -> Matrix
transpose m@(M_ {nrows= r, ncols= c}) = matrix c r $
                                        \(Tuple i j) -> unsafeGet  j i m

-------------------------------------------------------
-------------------------------------------------------
---- MATRIX OPERATIONS
-- | Perform an operation element-wise.
--   The second matrix must have at least as many rows
--   and columns as the first matrix. If it's bigger,
--   the leftover items will be ignored.
--   If it's smaller, it will cause a run-time error.
--   You may want to use 'elementwiseUnsafe' if you
--   are definitely sure that a run-time error won't
--   arise.

-- | Unsafe version of 'elementwise', but faster.
elementwiseUnsafe :: (Number -> Number -> Number) -> (Matrix -> Matrix -> Matrix)
elementwiseUnsafe f m@(M_ {nrows= r, ncols= c}) m' = matrix r c $
          \(Tuple i j) -> f (unsafeGet i j m) (unsafeGet i j m')

-- instance Semiring Matrix where
--   add  = elementwiseUnsafe (+)
--   mul  = multStd
--   zero = undefined
--   one  = undefined
-- instance Ring Matrix where
--   sub = elementwiseUnsafe (-)

-- | Standard matrix multiplication by definition.
multStd :: Matrix -> Matrix -> Matrix
multStd a1@(M_ {nrows= n, ncols= m}) a2@(M_ {nrows= n', ncols= m'})
  | m /= n' = error $ "Matrix multiplication of " ++ sizeStr n m ++ " and "
                    ++ sizeStr n' m' ++ " matrices."
   | otherwise = multStd_ a1 a2

-- | Standard matrix multiplication by definition, without checking if sizes match.
multStd_ :: Matrix -> Matrix -> Matrix
multStd_ a@(M_ {nrows= 1, ncols= 1}) b@(M_ {nrows= 1, ncols= 1}) =
  M_ {nrows= 1, ncols= 1, roff= 0, coff= 0, vcols= 1, values= v} where
    v = A.singleton $ (unsafeGet 1 1 a) * (unsafeGet 1 1 b)
multStd_ a@(M_ {nrows= 2, ncols= 2})
         b@(M_ {nrows= 2, ncols=  2}) =
  M_ {nrows= 2, ncols= 2, roff= 0, coff= 0, vcols= 2, values= v} where
    a11 = unsafeGet 1 1 a
    a12 = unsafeGet 1 2 a
    a21 = unsafeGet 2 1 a
    a22 = unsafeGet 2 2 a
    b11 = unsafeGet 1 1 b
    b12 = unsafeGet 1 2 b
    b21 = unsafeGet 2 1 b
    b22 = unsafeGet 2 2 b
    v = A.fromList [ a11*b11 + a12*b21 , a11*b12 + a12*b22
         , a21*b11 + a22*b21 , a21*b12 + a22*b22
        ]
multStd_ a@(M_ {nrows= 3, ncols= 3})
         b@(M_ {nrows= 3, ncols= 3}) =
  M_ {nrows= 3, ncols= 3, roff= 0, coff= 0, vcols= 3, values= v} where
    a11 = unsafeGet 1 1 a
    a12 = unsafeGet 1 2 a
    a13 = unsafeGet 1 3 a
    a21 = unsafeGet 2 1 a
    a22 = unsafeGet 2 2 a
    a23 = unsafeGet 2 3 a
    a31 = unsafeGet 3 1 a
    a32 = unsafeGet 3 2 a
    a33 = unsafeGet 3 3 a
    b11 = unsafeGet 1 1 b
    b12 = unsafeGet 1 2 b
    b13 = unsafeGet 1 3 b
    b21 = unsafeGet 2 1 b
    b22 = unsafeGet 2 2 b
    b23 = unsafeGet 2 3 b
    b31 = unsafeGet 3 1 b
    b32 = unsafeGet 3 2 b
    b33 = unsafeGet 3 3 b
    v = A.fromList [ a11*b11 + a12*b21 + a13*b31
        , a11*b12 + a12*b22 + a13*b32
        , a11*b13 + a12*b23 + a13*b33
        , a21*b11 + a22*b21 + a23*b31
        , a21*b12 + a22*b22 + a23*b32
        , a21*b13 + a22*b23 + a23*b33
        , a31*b11 + a32*b21 + a33*b31
        , a31*b12 + a32*b22 + a33*b32
        , a31*b13 + a32*b23 + a33*b33
        ]
multStd_ a@(M_ {nrows= n, ncols= m}) b@(M_ {ncols= m'}) =
  matrix n m' $ \(Tuple i j) -> sum $ do
    k <- [1 .. m]
    pure $ (unsafeGet i k a ) * (unsafeGet k j b)

