module Dependencies (testDependencies) where

import Test.Tasty
import Test.Tasty.Runners
import Test.Tasty.Options
import Test.Tasty.HUnit
import Control.Concurrent
import Control.Concurrent.STM
import Text.Printf
import qualified Data.IntMap as IntMap
import Control.Monad
#if !MIN_VERSION_base(4,8,0)
import Data.Monoid (mempty)
#endif

-- this is a dummy tree we use for testing
testTree :: DependencyType -> Bool -> TestTree
testTree deptype succeed =
  testGroup "dependency test"
    [ after deptype "Three" $ testCase "One" $ threadDelay 1e6
    , testCase "Two" $ threadDelay 1e6
    , testCase "Three" $ threadDelay 1e6 >> assertBool "fail" succeed
    ]

testDependencies :: TestTree
testDependencies = testGroup "Dependencies" $ do
  succeed <- [True, False]
  deptype <- [AllSucceed, AllFinish]
  return $ testCase (printf "%-5s %s" (show succeed) (show deptype)) $ do
    launchTestTree (singleOption $ NumThreads 2) (testTree deptype succeed) $ \smap -> do
      let all_tests@[one, two, three] = IntMap.elems smap
      -- at first, no tests have finished yet
      threadDelay 2e5
      forM_ all_tests $ \tv -> do
        st <- atomically $ readTVar tv
        assertBool (show st) $
          case st of
            Done {} -> False
            _ -> True

      -- after ≈ 1 second, the second and third tests will have finished;
      -- the first will have not unless it is skipped because the first one
      -- failed
      threadDelay 11e5
      st <- atomically $ readTVar three
      assertBool (show st) $
        case st of
          Done r -> resultSuccessful r == succeed
          _ -> False
      st <- atomically $ readTVar two
      assertBool (show st) $
        case st of
          Done r -> resultSuccessful r == True
          _ -> False
      st <- atomically $ readTVar one
      assertBool (show st) $
        case st of
          Done _ | succeed || deptype == AllFinish -> False
          _ -> True

      -- after ≈ 2 seconds, the third test will have finished as well
      threadDelay 1e6
      st <- atomically $ readTVar one
      assertBool (show st) $
        case st of
          Done r
            | succeed || deptype == AllFinish -> resultSuccessful r
            | otherwise ->
                case resultOutcome r of
                  Failure TestDepFailed -> True
                  _ -> False
          _ -> False

      return $ const $ return ()