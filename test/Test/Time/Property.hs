-- SPDX-FileCopyrightText: 2019 Serokell <https://serokell.io>
--
-- SPDX-License-Identifier: MPL-2.0

{-# LANGUAGE CPP                 #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE ExplicitForAll      #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE KindSignatures      #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications    #-}

module Test.Time.Property
       ( hedgehogTestTrees
       ) where

import GHC.Natural (Natural)
import GHC.Real ((%))
import Hedgehog (MonadGen, MonadTest, Property, PropertyT, forAll, property, (===))
import Test.Tasty (TestTree)
import Test.Tasty.Hedgehog (testProperty)

import Time (Day, Fortnight, Hour, KnownRat, KnownRatName, Microsecond,
             Millisecond, Minute, Nanosecond, Picosecond, Rat, RatioNat, Second,
             Time (..), Week, toUnit, unitsF, unitsP)
import Time (withRuntimeDivRat)

import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

hedgehogTestTrees :: [TestTree]
hedgehogTestTrees = [readShowTestTree, toUnitTestTree, seriesTestTree]

readShowTestTree :: TestTree
readShowTestTree = testProperty "Hedgehog read . show == id" prop_readShowUnit

toUnitTestTree :: TestTree
toUnitTestTree = testProperty "Hedgehog toUnit @to @from . toUnit @from @to ≡ id' property" prop_toUnit

seriesTestTree :: TestTree
seriesTestTree = testProperty "Hedgehog unitsP . unitsF ≡ id" prop_series

-- | Existential data type for 'Unit's.
data AnyTime =  forall (unit :: Rat) . (KnownRatName unit)
             => MkAnyTime (Time unit)

instance Show AnyTime where
    show (MkAnyTime t) = show t

-- | Returns random 'AnyTime'.
unitChooser :: (MonadGen m) => RatioNat -> m AnyTime
unitChooser t = Gen.element
    [ MkAnyTime (Time @Second      t)
    , MkAnyTime (Time @Millisecond t)
    , MkAnyTime (Time @Microsecond t)
    , MkAnyTime (Time @Nanosecond  t)
    , MkAnyTime (Time @Picosecond  t)
    , MkAnyTime (Time @Minute      t)
    , MkAnyTime (Time @Hour        t)
    , MkAnyTime (Time @Day         t)
    , MkAnyTime (Time @Week        t)
    , MkAnyTime (Time @Fortnight   t)
    ]

-- | Verifier for 'AnyTime' @read . show = id@.
verifyAnyTime :: (MonadTest m) => AnyTime -> m ()
verifyAnyTime (MkAnyTime t) = read (show t) === t

-- | Verifier for 'toUnit'.
verifyToUnit :: forall m . (MonadTest m) => AnyTime -> AnyTime -> m ()
verifyToUnit (MkAnyTime t1) (MkAnyTime t2) = checkToUnit t1 t2
  where
    checkToUnit :: forall (unitFrom :: Rat) (unitTo :: Rat) .
                   (KnownRatName unitFrom, KnownRat unitTo)
                => Time unitFrom
                -> Time unitTo
                -> m ()
    checkToUnit t _ =
                      withRuntimeDivRat @unitTo @unitFrom $
                      withRuntimeDivRat @unitFrom @unitTo $
                      toUnit (toUnit @unitTo t) === t

-- | Verifier for @ seriesP . seriesF @.
verifySeries :: forall m . (MonadTest m) => AnyTime -> m ()
verifySeries (MkAnyTime anyT) = checkSeries anyT
  where
    checkSeries :: forall (unit :: Rat) . KnownRatName unit
                => Time unit -> m ()
    checkSeries t = unitsP @unit (unitsF t) === Just t

-- | Generates random natural number up to 10^20.
-- it receives the lower bound so that it wouldn't be possible
-- to get 0 for denominator.
natural :: (MonadGen m) => Natural -> m Natural
natural n = Gen.integral (Range.constant n $ 10 ^ (20 :: Int))

-- | Generates random rational number.
rationalNum :: (MonadGen m) => m RatioNat
rationalNum = do
    numeratorVal <- natural 0
    isOne        <- Gen.bool
    denomVal     <- if isOne then pure 1
                             else natural 1
    return $ numeratorVal % denomVal

anyTime :: (MonadGen m) => m AnyTime
anyTime = rationalNum  >>= unitChooser

genAnyTime :: Monad m => PropertyT m AnyTime
genAnyTime = forAll anyTime

-- | Property test.
prop_readShowUnit :: Property
prop_readShowUnit = property $ genAnyTime >>= verifyAnyTime

prop_toUnit :: Property
prop_toUnit = property $ do
    t1 <- genAnyTime
    t2 <- genAnyTime
    verifyToUnit t1 t2

prop_series :: Property
prop_series = property $ genAnyTime >>= verifySeries
