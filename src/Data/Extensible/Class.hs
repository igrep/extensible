{-# LANGUAGE MultiParamTypeClasses, UndecidableInstances, ScopedTypeVariables, TypeFamilies #-}
#if __GLASGOW_HASKELL__ >= 800
{-# LANGUAGE UndecidableSuperClasses #-}
#endif
-----------------------------------------------------------------------------
-- |
-- Module      :  Data.Extensible.Class
-- Copyright   :  (c) Fumiaki Kinoshita 2018
-- License     :  BSD3
--
-- Maintainer  :  Fumiaki Kinoshita <fumiexcel@gmail.com>
--
-----------------------------------------------------------------------------
module Data.Extensible.Class (
  -- * Class
   Extensible(..)
  , piece
  , pieceAssoc
  , itemAt
  , item
  , itemAssoc
  -- * Membership
  , Membership
  , mkMembership
  , getMemberId
  , compareMembership
  , leadership
  -- * Member
  , Member(..)
  , remember
#if __GLASGOW_HASKELL__ >= 800
  , type (∈)
#else
  , (∈)()
#endif
  , FindType
  -- * Generation
  , Generate(..)
  , Forall(..)
  , ForallF
  -- * Association
  , Assoc(..)
#if __GLASGOW_HASKELL__ >= 800
  , type (>:)
#else
  , (>:)()
#endif
  , Associate(..)
  , FindAssoc
  -- * Sugar
  , Elaborate
  , Elaborated(..)
  ) where
import Data.Constraint
import Data.Extensible.HList
import Data.Extensible.Internal
import Data.Extensible.Internal.Rig (Optic')
import Data.Extensible.Wrapper
import Data.Profunctor

-- | This class allows us to use 'pieceAt' for both sums and products.
class (Functor f, Profunctor p) => Extensible f p (t :: (k -> *) -> [k] -> *) where
  type ExtensibleConstr t (h :: k -> *) (xs :: [k]) (x :: k) :: Constraint
  type ExtensibleConstr t h xs x = ()
  pieceAt :: ExtensibleConstr t h xs x => Membership xs x -> Optic' p f (t h xs) (h x)

-- | Accessor for an element.
piece :: (x ∈ xs, Extensible f p t, ExtensibleConstr t h xs x) => Optic' p f (t h xs) (h x)
piece = pieceAt membership
{-# INLINE piece #-}

-- | Like 'piece', but reckon membership from its key.
pieceAssoc :: (Associate k v xs, Extensible f p t, ExtensibleConstr t h xs (k ':> v)) => Optic' p f (t h xs) (h (k ':> v))
pieceAssoc = pieceAt association
{-# INLINE pieceAssoc #-}

-- | Access a specified element through a wrapper.
itemAt :: (Wrapper h, Extensible f p t, ExtensibleConstr t h xs x) => Membership xs x -> Optic' p f (t h xs) (Repr h x)
itemAt m = pieceAt m . _Wrapper
{-# INLINE itemAt #-}

-- | Access an element through a wrapper.
item :: (Wrapper h, Extensible f p t, x ∈ xs, ExtensibleConstr t h xs x) => proxy x -> Optic' p f (t h xs) (Repr h x)
item p = piece . _WrapperAs p
{-# INLINE item #-}

-- | Access an element specified by the key type through a wrapper.
itemAssoc :: (Wrapper h, Extensible f p t, Associate k v xs, ExtensibleConstr t h xs (k ':> v))
  => proxy k -> Optic' p f (t h xs) (Repr h (k ':> v))
itemAssoc p = pieceAssoc . _WrapperAs (proxyKey p)
{-# INLINE itemAssoc #-}

proxyKey :: proxy k -> Proxy (k ':> v)
proxyKey _ = Proxy
{-# INLINE proxyKey #-}

-- | Every type-level list is an instance of 'Generate'.
class Generate (xs :: [k]) where
  -- | Enumerate all possible 'Membership's of @xs@.
  henumerate :: (forall x. Membership xs x -> r -> r) -> r -> r

  -- | Count the number of memberships.
  hcount :: proxy xs -> Int

  -- | Enumerate 'Membership's and construct an 'HList'.
  hgenerateList :: Applicative f
    => (forall x. Membership xs x -> f (h x)) -> f (HList h xs)

instance Generate '[] where
  henumerate _ r = r

  hcount _ = 0

  hgenerateList _ = pure HNil

instance Generate xs => Generate (x ': xs) where
  henumerate f r = f here $ henumerate (f . navNext) r

  hcount _ = 1 + hcount (Proxy :: Proxy xs)

  -- | Enumerate 'Membership's and construct an 'HList'.
  hgenerateList f = HCons <$> f here <*> hgenerateList (f . navNext)

-- | Every element in @xs@ satisfies @c@
class (ForallF c xs, Generate xs) => Forall (c :: k -> Constraint) (xs :: [k]) where
  -- | Enumerate all possible 'Membership's of @xs@ with an additional context.
  henumerateFor :: proxy c -> proxy' xs -> (forall x. c x => Membership xs x -> r -> r) -> r -> r

  hgenerateListFor :: Applicative f
    => proxy c -> (forall x. c x => Membership xs x -> f (h x)) -> f (HList h xs)

instance Forall c '[] where
  henumerateFor _ _ _ r = r

  hgenerateListFor _ _ = pure HNil

instance (c x, Forall c xs) => Forall c (x ': xs) where
  henumerateFor p _ f r = f here $ henumerateFor p (Proxy :: Proxy xs) (f . navNext) r

  hgenerateListFor p f = HCons <$> f here <*> hgenerateListFor p (f . navNext)

-- | HACK: Without this, the constraints are not propagated well.
type family ForallF (c :: k -> Constraint) (xs :: [k]) :: Constraint where
  ForallF c '[] = ()
  ForallF c (x ': xs) = (c x, Forall c xs)
