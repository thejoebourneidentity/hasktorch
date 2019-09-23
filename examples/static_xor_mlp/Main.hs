{-# LANGUAGE DataKinds #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE UndecidableSuperClasses #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE NoStarIsType #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import           Prelude                 hiding ( tanh )
import           Control.Monad                  ( foldM
                                                , when
                                                )
import           Data.List                      ( foldl'
                                                , scanl'
                                                , intersperse
                                                )
import           Data.Reflection
import           GHC.Generics
import           GHC.TypeLits

import           Torch.Static
import           Torch.Static.Native     hiding ( linear )
import           Torch.Static.Factories
import qualified Torch.Autograd                as A
import qualified Torch.NN                      as A
import qualified Torch.DType                   as D
import qualified Torch.Tensor                  as D
import qualified Torch.Functions               as D
import qualified Torch.TensorFactories         as D


--------------------------------------------------------------------------------
-- MLP
--------------------------------------------------------------------------------


newtype Parameter d s = Parameter A.IndependentTensor deriving (Show)

toDependent :: Parameter d s -> Tensor d s
toDependent (Parameter t) = UnsafeMkTensor $ A.toDependent t

instance A.Parameterized (Parameter d s) where
  flattenParameters (Parameter x) = [x]
  replaceOwnParameters _ = Parameter <$> A.nextParameter

data LinearSpec (d::D.DType) (i::Nat) (o::Nat) = LinearSpec
  deriving (Show, Eq)

data Linear (d::D.DType) (in_features::Nat) (out_features::Nat) =
  Linear { weight :: Parameter d '[in_features,out_features]
         , bias :: Parameter d '[out_features]
         } deriving (Show, Generic)

linear :: Linear d i o -> Tensor d '[k, i] -> Tensor d '[k, o]
linear Linear {..} input =
  add (mm input (toDependent weight)) (toDependent bias)

makeIndependent :: Tensor d s -> IO (Parameter d s)
makeIndependent t = Parameter <$> A.makeIndependent (toDynamic t)

instance A.Parameterized (Linear d n m)

instance (KnownDType d, KnownNat n, KnownNat m) => A.Randomizable (LinearSpec d n m) (Linear d n m) where
  sample LinearSpec = do
    w <- makeIndependent =<< (randn :: IO (Tensor d '[n, m]))
    b <- makeIndependent =<< (randn :: IO (Tensor d '[m]))
    return $ Linear w b

data MLPSpec (d::D.DType) (i::Nat) (o::Nat) (h::Nat) = MLPSpec

data MLP (d::D.DType) (i::Nat) (o::Nat) (h::Nat) =
  MLP { l0 :: Linear d i h
      , l1 :: Linear d h h
      , l2 :: Linear d h o
      } deriving (Generic)

instance A.Parameterized (MLP d i o h)

instance (KnownDType d, KnownNat n, KnownNat m, KnownNat h) => A.Randomizable (MLPSpec d n m h) (MLP d n m h) where
  sample MLPSpec = do
    l0 <- A.sample LinearSpec :: IO (Linear d n h)
    l1 <- A.sample LinearSpec :: IO (Linear d h h)
    l2 <- A.sample LinearSpec :: IO (Linear d h m)
    return $ MLP { .. }

mlp :: MLP d i o h -> Tensor d '[b, i] -> Tensor d '[b, o]
mlp MLP {..} = linear l2 . tanh . linear l1 . tanh . linear l0

model :: MLP d i o h -> Tensor d '[n, i] -> Tensor d '[n, o]
model = (sigmoid .) . mlp

batchSize = 32
numIters = 10000

main = do
  init    <- A.sample (MLPSpec :: MLPSpec 'D.Float 2 1 20)
  trained <- foldLoop init numIters $ \state i -> do
    input <- D.toDType D.Float . D.gt 0.5 <$> D.rand' [batchSize, 2]
    let expected_output = tensorXOR input

    let output = D.squeezeAll . toDynamic $ model
          state
          (UnsafeMkTensor input :: Tensor 'D.Float '[batchSize, 2])
    let loss            = D.mse_loss output expected_output

    let flat_parameters = A.flattenParameters state
    let gradients       = A.grad loss flat_parameters

    when (i `mod` 100 == 0) (print loss)

    new_flat_parameters <- mapM A.makeIndependent
      $ A.sgd 5e-4 flat_parameters gradients
    return $ A.replaceParameters state new_flat_parameters
  return ()
 where
  foldLoop x count block = foldM block x [1 .. count]
  tensorXOR t = (1 - (1 - a) * (1 - b)) * (1 - (a * b))
   where
    a = D.select t 1 0
    b = D.select t 1 1
