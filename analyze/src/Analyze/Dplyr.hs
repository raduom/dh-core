{-# language OverloadedStrings #-}
{-# language FlexibleInstances #-}
{-# language DeriveFunctor, DeriveFoldable, DeriveTraversable #-}
module Analyze.Dplyr where

import Analyze.RFrame
import Analyze.Common

import Control.Applicative (Alternative(..))
import qualified Data.Foldable as F
import qualified Data.Vector as V
import qualified Data.HashMap.Strict as HM
import qualified Data.List.NonEmpty as NE
import Data.Hashable (Hashable(..))

import Prelude hiding (filter, zipWith, lookup)


      
-- | Filter the RFrame rows according to a predicate applied to a column value
filterByKey :: Key k =>
               (v -> Bool) -- ^ Predicate 
            -> k           -- ^ Column key
            -> RFrame k v  
            -> Maybe (RFrame k v)
filterByKey qv k (RFrame ks hm vs) = do
  vsf <- V.filterM ff vs
  pure $ RFrame ks hm vsf
  where 
    ff vrow = do
      i <- HM.lookup k hm
      v <- vrow V.!? i
      pure $ qv v


  

-- * Relational operations



-- | Orders
t0 :: Table (Row String String)
t0 = fromList [ book, ball, bike, book ] where
  book = fromListR [("item", "book"), ("id.0", "129"), ("qty", "1")]
  ball = fromListR [("item", "ball"), ("id.0", "234"), ("qty", "1")]  
  bike = fromListR [("item", "bike"), ("id.0", "410"), ("qty", "1")]

-- | Prices
t1 :: Table (Row String String)
t1 = fromList [ r1, r2, r3, r4 ] where
  r1 = fromListR [("id.1", "129"), ("price", "100")]
  r2 = fromListR [("id.1", "234"), ("price", "50")]  
  r3 = fromListR [("id.1", "3"), ("price", "150")]
  r4 = fromListR [("id.1", "99"), ("price", "30")]


-- | INNER JOIN
--
-- > innerJoin "id.0" "id.1" t0 t1
-- Just [
--    [("id.1","129"),("id.0","129"),("qty","1"),("item","book"),("price","100")],
--    [("id.1","234"),("id.0","234"),("qty","1"),("item","ball"),("price","50")],
--    [("id.1","129"),("id.0","129"),("qty","1"),("item","book"),("price","100")]]
innerJoin :: (Foldable t, Hashable v, Hashable k, Eq v, Eq k) =>
             k -> k -> t (Row k v) -> t (Row k v) -> Maybe [Row k v]
innerJoin k1 k2 table1 table2 = F.foldlM insf [] table1 where
  insf acc row1 = do
    v <- lookup k1 row1
    matchRows2 <- matchingRows k2 v table2 <|> Just []
    let rows' = map (union row1) matchRows2
    pure (rows' ++ acc)

-- | Return all rows that match a value at a given key
matchingRows :: (Foldable t, Hashable v, Hashable k, Eq v, Eq k) =>
                k
             -> v
             -> t (Row k v)
             -> Maybe [Row k v]
matchingRows k v rows = do
  rowMap <- hjBuild k rows
  HM.lookup v rowMap

-- | "build" phase of the hash-join algorithm
hjBuild :: (Foldable t, Hashable a, Hashable k, Eq a, Eq k) =>
            k -> t (Row k a) -> Maybe (HM.HashMap a [Row k a])
hjBuild k = F.foldlM insf HM.empty where
  insf hmAcc row = do
    v <- lookup k row
    let hm' = HM.insertWith mappend v [row] hmAcc
    pure hm'


-- | A 'Row' type is internally a hashmap:
--
-- * logarithmic random access
-- * 
newtype Row k v = Row { unRow :: HM.HashMap k v } deriving (Eq)
instance (Show k, Show v) => Show (Row k v) where
  show = show . HM.toList . unRow
fromListR :: (Eq k, Hashable k) => [(k, v)] -> Row k v
fromListR = Row . HM.fromList
lookup :: (Eq k, Hashable k) => k -> Row k v -> Maybe v
lookup k = HM.lookup k . unRow
lookupDefault :: (Eq k, Hashable k) => v -> k -> Row k v -> v
lookupDefault v k = HM.lookupDefault v k . unRow
keys :: Row k v -> [k]
keys = HM.keys . unRow
union :: (Eq k, Hashable k) => Row k v -> Row k v -> Row k v
union r1 r2 = Row $ HM.union (unRow r1) (unRow r2)
unionWith :: (Eq k, Hashable k) =>
             (v -> v -> v) -> Row k v -> Row k v -> Row k v
unionWith f r1 r2 = Row $ HM.unionWith f (unRow r1) (unRow r2)

newtype Table row = Table {
    -- nTableRows :: Maybe Int  -- ^ Nothing means unknown
    tableRows :: NE.NonEmpty row } deriving (Eq, Show, Functor, Foldable, Traversable)

fromNEList :: [row] -> Maybe (Table row)
fromNEList l = Table <$> NE.nonEmpty l

fromList :: [row] -> Table row
fromList = Table . NE.fromList 

zipWith :: (a -> b -> row)
        -> Table a -> Table b -> Table row
zipWith f tt1 tt2 = Table $ NE.zipWith f (tableRows tt1) (tableRows tt2)

unionRowsWith :: (Eq k, Hashable k) =>
                 (v -> v -> v) -> Table (Row k v) -> Table (Row k v) -> Table (Row k v)
unionRowsWith f = zipWith (unionWith f)







-- | Polymorphic representation. A bit verbose

-- newtype GTable f k v = GTable { gTableRows :: f (HM.HashMap k v) }

-- instance (Show k, Show v) => Show (GTable U k v) where
--   show (GTable rows) = show rows
-- instance (Eq k, Eq v) => Eq (GTable U k v) where
--   GTable rows1 == GTable rows2 = rows1 == rows2
-- instance (Show k, Show v) => Show (GTable B k v) where
--   show (GTable rows) = show rows
-- instance (Eq k, Eq v) => Eq (GTable B k v) where
--   GTable rows1 == GTable rows2 = rows1 == rows2  

-- newtype B rows = B (NE.NonEmpty rows) deriving (Eq, Show)

-- newtype U rows = U [rows] deriving (Eq, Show)

-- newtype BTable k v = BTable { unBTable :: GTable B k v } -- deriving (Eq, Show)
-- newtype UTable k v = UTable { unUTable :: GTable U k v }