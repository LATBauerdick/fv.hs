-- file src/Fit.hs
module Types (
  M, V, M33, V3, V5, C44, XMeas (..), HMeas (..), QMeas (..)
             , PMeas (..), MMeas (..), Prong (..), VHMeas (..)
             , X3, C33, Q3, H5, C55
             , ABh0 (..), Chi2
             , showXMeas, showPMeas, showQMeas, showMMeas, showHMeas
             , showXMDist, origin
             , h2p, h2q, q2p
             , mπ
             ) where

import Text.Printf
import qualified Data.Matrix ( Matrix, getDiag, getCol, toList, zero
                             , fromLists, transpose )
import qualified Data.Vector ( zip, map, fromList, toList, drop )
import qualified Matrix ( scalar, sw, tr, sub, sub2, toList, fromList, fromList2 )

mπ :: Double
mπ = 0.1395675E0


type M     = Data.Matrix.Matrix Double
type V     = Data.Matrix.Matrix Double
type M33   = Data.Matrix.Matrix Double
type V3    = Data.Matrix.Matrix Double
type V5    = Data.Matrix.Matrix Double
type N     = Int
type Chi2  = Double
data Prong = Prong N XMeas [QMeas] [Chi2] deriving Show -- a prong results from a vertex fit of N helices

data VHMeas a = VHMeas XMeas [a] deriving Show
instance Monoid (VHMeas a) where
  mappend (VHMeas v as) (VHMeas v' as') = VHMeas (v) ( as ++ as' ) -- ???
instance Functor VHMeas where -- apply f to each a
  fmap f (VHMeas v (a:as)) = VHMeas v ((f a):(fmap f as))

data ABh0 = ABh0 M M M

type X3 = V
type C33 = M
data XMeas = XMeas X3 C33 deriving Show -- 3-vector and covariance matrix for position/vertex measurement

type H5 = V
type C55 = M
data HMeas = HMeas H5 C55 Double deriving Show -- 5-vector and covariance matrix for helix measurement

type Q3 = V
data QMeas = QMeas Q3 C33 Double deriving Show -- 3-vector and covariance matrix for momentum measurement

-- 4-vector and coavariance matrix for momentum px,py,pz and energy
type P4 = V -- four-vector
type C44 = M -- 4x4 covariance matrix
data PMeas = PMeas P4 C44 deriving Show
instance Monoid (PMeas) where
  mappend (PMeas p1 cp1) (PMeas p2 cp2) = PMeas (p1+p2) (cp1 + cp2)
  mempty = PMeas (Data.Matrix.fromLists [[0.0,0.0,0.0,0.0]])
            ((Data.Matrix.zero 4 4)::C44)
-- instance Functor PMeas where
--   fmap f (PMeas p cp) = f p cp

type D = Double
data MMeas = MMeas D D deriving Show -- mass and error

-- show instances -- refactor!!

-- return a string showing vertext position vector with errors
showXMeas :: String -> XMeas -> String
showXMeas s (XMeas v cv) = s' where
  s2v        = Data.Vector.map sqrt $ Data.Matrix.getDiag cv
  f :: String -> (Double, Double) -> String
  f s (x, dx)  = s ++ printf "%8.3f ± %8.3f" (x::Double) (dx::Double)
  s' = (foldl f s $ Data.Vector.zip (Data.Matrix.getCol 1 v) s2v) ++ " cm"

-- calculate distance between two vertices
showXMDist :: String -> XMeas -> XMeas -> String
showXMDist s0 (XMeas v0 vv0) (XMeas v1 vv1) = s where
  [x0, y0, z0] = Matrix.toList 3 v0
  [x1, y1, z1] = Matrix.toList 3 v1

  d    = sqrt((x0-x1)**2 + (y0-y1)**2 + (z0-z1)**2)

  dd   = Data.Matrix.fromLists [[(x0-x1)/d, (y0-y1)/d, (z0-z1)/d]]
  tem0 = Matrix.sw (Matrix.tr dd) vv0
  tem1 = Matrix.sw (Matrix.tr dd) vv1
  sd   = sqrt (Matrix.scalar tem0 + Matrix.scalar tem1)
  s    = printf (s0++"%8.3f ± %8.3f cm")(d::Double) (sd::Double)

origin :: XMeas
origin = (XMeas (Data.Matrix.fromLists [[0.0,0.0,0.0]])
            ((Data.Matrix.zero 3 3)::C33))

showMMeas :: String -> MMeas -> IO ()
showMMeas s (MMeas m dm) = do
  putStr s
  printf "%8.3f ± %8.3f" (m::Double) (dm::Double)
  putStrLn " GeV"

-- print PMeas as a 4-momentum vector px,py,pz,E with errors
showPMeas :: String -> PMeas -> IO ()
showPMeas s (PMeas p cp) = do
  putStr s
  let
    sp         = Data.Vector.map sqrt $ Data.Matrix.getDiag cp
    f (x, dx)  = printf "%8.3f ± %8.3f" (x::Double) (dx::Double)
    in mapM_ f $ Data.Vector.zip (Data.Matrix.getCol 1 p) sp
  putStrLn " GeV"


-- print HMeas as a 5-parameter helix with errors
showHMeas :: String -> HMeas -> String
showHMeas s (HMeas h ch w2pt) = s' where
  sh           = Data.Vector.map sqrt $ Data.Matrix.getDiag ch
  f s (x, dx)  = s ++ printf "%8.3f ± %8.3f" (x::Double) (dx::Double)
  s'' = s ++ printf "%10.5g ± %10.5g" (x::Double) (dx::Double) where
    x  = head (Data.Matrix.toList h)
    dx = head (Data.Vector.toList sh)
  s' = foldl f s'' (Data.Vector.drop 1 $ Data.Vector.zip (Data.Matrix.getCol 1 h) sh)

-- print QMeas as a 4-momentum vector with errors, use pt and pz
showQMeas :: String -> QMeas -> IO ()
showQMeas s (QMeas q cq w2pt) = do
  putStr s
  let
    f (x, dx)    = printf "%8.3f ± %8.3f" (x::Double) (dx::Double)
    m = mπ
    wp = w2pt
    [w,tl,psi0] = take 3 (Data.Matrix.toList q)
    pt   = wp / abs w
    pz = pt/tl
    psi = psi0*180.0/pi
    e = sqrt(pt^2  + pz^2 + m^2)
    jj   = Data.Matrix.fromLists [
            [-wp/w/w, -wp/w/w*tl,0, -(pz*pz + pt*pt)/w/e ]
          , [0, wp/w, 0, pt*pt*tl/e]
          , [0, 0, 1.0, 0] ]
    cq'  = (Data.Matrix.transpose jj) * cq* jj
    p'   = Data.Vector.fromList [pt, pz, psi, e]
--    dp'  = Data.Vector.map sqrt $ Data.Matrix.getDiag cq'
    [d1,d2,d3,d4]  = Data.Vector.toList $ Data.Vector.map sqrt $ Data.Matrix.getDiag cq'
    dp' = Data.Vector.fromList [d1,d2,d3*180.0/pi,d4]
    in mapM_ f $ Data.Vector.zip p' dp'
  putStrLn " GeV"


h2p :: HMeas -> PMeas
h2p hm = (q2p . h2q) hm

h2q :: HMeas -> QMeas -- just drop the d0, z0 part... fix!!!!
h2q (HMeas h ch w2pt) = QMeas q cq w2pt where
  q = (Matrix.sub 3 h)
  cq = (Matrix.sub2 3 ch)

q2p :: QMeas -> PMeas
q2p (QMeas q0 cq0 w2pt) = (PMeas p0 cp0) where
  m = mπ
  [w,tl,psi0] = Matrix.toList 3 q0
  sph  = sin psi0
  cph  = cos psi0
  pt   = w2pt / abs w
  px   = pt * cph
  py   = pt * sph
  pz   = pt / tl
  e = sqrt(px^2 + py^2 + pz^2 + m^2)
  ps = w2pt / w
  dpdk = ps*ps/w2pt
  [c11, c12, c13, _, c22, c23, _, _, c33] = Matrix.toList 9 cq0
  xy = 2.0*ps*dpdk*cph*sph*c13
  sxx = (dpdk*cph)^2 * c11 + (ps*sph)^2 * c33 + xy
  sxy = cph*sph*(dpdk*dpdk*c11 - ps*ps*c33) +
           ps*dpdk*(sph*sph-cph*cph)*c13
  syy = (dpdk*sph)^2 * c11 + (ps*cph)^2 * c33 - xy
  -- check jacobian now that pz = pt/tl????????????????????????
  sxz = dpdk*dpdk*cph*tl*c11 -
           ps*dpdk*(cph*c12-sph*tl*c13) -
           ps*ps*sph*c23
  syz = dpdk*dpdk*sph*tl*c11 -
           ps*dpdk*(sph*c12 + cph*tl*c13) +
           ps*ps*cph*c23
  szz = (dpdk*tl)^2 * c11 + ps*ps*c22 -
           2.0*ps*dpdk*tl*c12
  sxe = (px*sxx + py*sxy + pz*sxz)/e
  sye = (px*sxy + py*syy + pz*syz)/e
  sze = (px*sxz + py*syz + pz*szz)/e
  see = (px*px*sxx + py*py*syy + pz*pz*szz +
         2.0*(px*(py*sxy + pz*sxz) + py*pz*syz))/e/e

  p0 = Matrix.fromList 4 [px,py,pz,e]
  cp0 = Matrix.fromList2 4 4 [sxx, sxy, sxz, sxe, sxy, syy, syz, sye, sxz, syz, szz, sze, sxe, sye, sze, see]

-- q2pt :: QMeas -> PMeas
-- q2pt (QMeas q cq) = (PMeas p cp) where
--     m = mπ
--     wp = w2pt
--     [w,tl,psi0] = take 3 (Data.Matrix.toList q)
--     pt   = wp / abs w
--     pz = pt/tl
--     psi = psi0*180.0/pi
--     e = sqrt(pt^2  + pz^2 + m^2)
--     jj   = Data.Matrix.fromLists [
--             [-wp/w/w, -wp/w/w/tl,0, -(pz*pz + pt*pt)/w/e ]
--           , [0, -wp/w/tl/tl, 0, pt*pt*tl/e]
--           , [0, 0, 1.0, 0] ]
--     cp  = (Data.Matrix.transpose jj) * cq* jj
--     p   = Data.Vector.fromList [pt, pz, psi, e]

