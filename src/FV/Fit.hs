-- {-# LANGUAGE EmptyDataDecls #-}
{-# LANGUAGE ExplicitForAll #-}
--{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
-- {-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
--{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE RankNTypes #-}
--{-# LANGUAGE RebindableSyntax #-}
--{-# LANGUAGE ScopedTypeVariables #-}

{-# LANGUAGE OverloadedLists #-}
--{-# LANGUAGE NamedFieldPuns #-}

module FV.Fit (
                fit, kAddF, kAdd, ksm'
              , kChi2
              ) where

import Prelude.Extended
--import qualified Data.Vector.Unboxed as A ( foldl, unzip, length )
import Data.Maybe ( Maybe (..), mapMaybe, fromJust )

import Data.Cov
import FV.Jacob as J
import FV.Types ( VHMeas (..), HMeas (..), QMeas (..), XMeas (..)
                , XFit (..)
                , Prong (..), Chi2 (..)
                )

fit :: VHMeas -> Prong
fit vhm = kSmooth vhm <<< kFilter $ vhm

kFilter :: VHMeas -> XMeas
kFilter VHMeas {vertex=v, helices=hl} = foldl kAdd v hl

kAdd :: XMeas -> HMeas -> XMeas
kAdd (XMeas v vv) (HMeas h hh w0) = kAdd' x_km1 p_k x_e q_e (Chi2 1e6) 0 where
  x_km1 = XMeas v (inv vv)
  p_k   = HMeas h (inv hh) w0
  x_e   = v
  q_e   = J.hv2q h v

goodEnough :: Chi2 -> Chi2 -> Int -> Bool
--goodEnough (Chi2 c0) (Chi2 c) i | i < 99 && trace ("." <> tshow i <> "|" <> to1fix (abs (c-c0)) <> " " <> to1fix c) false = undefined
goodEnough (Chi2 c0) (Chi2 c) i = abs (c - c0) < chi2cut || i > iterMax where
  chi2cut = 0.5
  iterMax = 99 :: Int

-- | add a helix measurement to kalman filter, return updated vertex position
-- | if we can't invert, don't update vertex
kAdd' :: XMeas -> HMeas -> Vec3 -> Vec3 -> Chi2 -> Int -> XMeas
--kAdd' (XMeas v0 uu0) (HMeas h gg w0) x_e q_e _ i |
--        i == 0 && trace ("kadd'-->" <> tshow i <> "|" <> tshow v0 <> tshow h) false = undefined
kAdd' (XMeas v0 uu0) (HMeas h gg w0) x_e q_e (Chi2 𝜒2_0) iter
  | goodEnough = XMeas v cc
  | otherwise  = kAdd' (XMeas v0 uu0) (HMeas h gg w0) v q (Chi2 𝜒2) (iter+1)
  where
    Jacs {aajacs=aa, bbjacs=bb, h0jacs=h0} = J.expand x_e q_e
    aaT  = tr aa
    bbT  = tr bb
    ww   = fromJust $ invMaybe (bb .*. gg)
    gb   = gg - gg .*. (bbT .*. ww)
    uu   = uu0 + aa .*. gb
    cc   = inv uu
    m    = h - h0
    v    = cc *. (uu0 *. v0 + aaT *. gb *. m)
    dm   = m - aa *. v
    q    = ww *. (bbT *. gg *. dm)
    𝜒2   = (dm - bb *. q) .*. gg + (v - v0) .*. uu0
    goodEnough = abs (𝜒2 - 𝜒2_0) < chi2cut || iter > iterMax where
      chi2cut = 0.5
      iterMax = 99 :: Int

kAddF :: XFit -> HMeas -> XFit
kAddF (XFit v vv _) (HMeas h hh _) = kAddF' v (inv vv) h (inv hh) v (J.hv2q h v) (Chi2 1e6) 0

kAddF' :: Vec3 -> Cov3 -> Vec5 -> Cov5 -> Vec3 -> Vec3 -> Chi2 -> Int -> XFit
kAddF' v0 uu0 h gg x_e q_e 𝜒2_0 iter = x_k where
  jj    = J.expand x_e q_e
  Jacs {aajacs=aa, bbjacs=bb, h0jacs=h0} = jj
  aaT   = tr aa
  bbT   = tr bb
  x_k   = case invMaybe (bb .*. gg) of
            Nothing  -> XFit v0 (inv uu0) (Chi2 1e6)  `debug` "... can't invert in kAddF'"
            Just ww -> let
                gb    = gg - gg .*. (bbT .*. ww)
                uu    = uu0 + aa .*. gb
                cc    = inv uu
                m     = h - h0
                v     = cc *. (uu0 *. v0 + aaT *. gb *. m)
                dm    = m - aa *. v
                q     = ww *. (bbT *. gg *. dm)
                𝜒2    = Chi2 $ (dm - bb *. q) .*. gg + (v - v0) .*. uu0
                x_k'  = if goodEnough 𝜒2_0 𝜒2 iter -- `debug` (printf "--> kAddF' chi2 is %9.1f, %9.1f" 𝜒2 (scalar $ sw (v-v0) uu0))
                          then XFit v cc 𝜒2
                          else kAddF' v0 uu0 h gg v q 𝜒2 (iter+1)
              in x_k'

kSmooth :: VHMeas -> XMeas -> Prong
--kSmooth vm v | trace ("kSmooth " <> (tshow <<< length <<< helices $ vm) <> ", vertex at " <> (tshow v) ) false = undefined
kSmooth (VHMeas {vertex= v0, helices= hl}) v = pr' where
  (ql, chi2l) = unzip $ mapMaybe (ksm v) hl
  hl' = hl
  n = length hl
  n' = length ql
  n'' = if n == n' then n else n' `debug` "kSmooth killed helices"
  pr' = Prong { fitVertex= v, fitMomenta= ql, fitChi2s= chi2l, nProng= n'', measurements= VHMeas {vertex= v0, helices= hl'} }

-- kalman smoother step: calculate 3-mom q and chi2 at kalman filter'ed vertex
-- if we can't invert, return Nothing and this track will not be included
ksm :: XMeas -> HMeas -> Maybe (QMeas, Chi2)
ksm (XMeas x cc) (HMeas h hh w0) = do
  let
      jj = J.expand x (J.hv2q h x)
      Jacs {aajacs=aa, bbjacs=bb, h0jacs=h0} = jj
      gg = inv hh
  ww <- invMaybe (bb .*. gg)
  let p    = h - h0
      uu   = inv cc
      aaT  = tr aa
      bbT  = tr bb
      dp   = p - aa *. x
      q    = ww *. (bbT *. gg *. dp)
      mee   = (cc *. aaT) *. gg *. bb *. ww
      dd   = ww + mee .*. uu
      r    = p - aa *. x - bb *. q
      ch   = r .*. gg
      gb   = gg - gg .*. (bbT .*. ww)
      uu'  = uu - aa .*. gb
      cx   = if det uu' < 0.0 then 1000.0
                                `debug` ("--> ksm bad " <> tshow (det uu')
                                                        <> tshow uu')
                    else cx'' where
                      cc'  = inv uu' -- `debug` ("--> ksm " <> tshow uu')
                      x'   = cc' *. (uu *. x - aaT *. gb *. p)
                      dx   = x - x'
                      cx'  = dx .*. uu'
                      cx'' = if cx' < 0.0 then 2000.0 `debug` ("--> ksm chi2 is " <> tshow cx' <> ", " <> tshow ch <> ", " <> tshow (max cx' 0.0 + ch))
                                        else cx'
      𝜒2 = cx + ch
  pure (QMeas q dd w0, Chi2 𝜒2)

ksm' :: XMeas -> Maybe HMeas -> Maybe (QMeas, Chi2)
ksm' _ Nothing = Nothing
ksm' xm (Just hm) = ksm xm hm

-- calculate Chi2 of a new helix measurement using kalman filter
-- if we can't invert, return 0.0
kChi2 :: XMeas -> HMeas -> Chi2
kChi2 (XMeas v vv) (HMeas h hh w0) = kChi2' x_km1 p_k x_e q_e (Chi2 1e6) 0 where
  x_km1 = XMeas v (inv vv)
  p_k   = HMeas h (inv hh) w0
  x_e   = v
  q_e   = J.hv2q h v
kChi2' :: XMeas -> HMeas -> Vec3 -> Vec3 -> Chi2 -> Int -> Chi2
kChi2' (XMeas v0 uu0) (HMeas h gg w0) x_e q_e 𝜒2_0 iter = x_k where
  jj = J.expand x_e q_e
  Jacs {aajacs=aa, bbjacs=bb, h0jacs=h0} = jj
  aaT = tr aa
  bbT = tr bb
  x_k = case invMaybe (bb .*. gg) of
            Nothing -> Chi2 0.0
            Just ww -> let
                gb    = gg - gg .*. (bbT .*. ww)
                uu    = uu0 + aa .*. gb
                cc    = inv uu
                m     = h - h0
                v     = cc *. (uu0 *. v0 + aaT *. gb *. m)
                dm    = m - aa *. v
                q     = ww *. bbT *. gg *. dm
                𝜒2    = Chi2 $ (v - v0) .*. uu0 -- or shoud it use uu?? + sw (dm - bb * q) gg
                x_k'  = if goodEnough 𝜒2_0 𝜒2 iter
                  then 𝜒2
                  else kChi2' (XMeas v0 uu0) (HMeas h gg w0) v q 𝜒2 (iter+1)
              in x_k'
