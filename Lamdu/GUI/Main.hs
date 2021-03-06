{-# LANGUAGE RankNTypes #-}
module Lamdu.GUI.Main
    ( make
    , Env(..)
    ) where

import           Control.Lens.Operators
import           Data.CurAndPrev (CurAndPrev(..))
import           Data.Store.Transaction (Transaction)
import           Data.Vector.Vector2 (Vector2(..))
import qualified Graphics.UI.Bottle.EventMap as EventMap
import           Graphics.UI.Bottle.Widget (Widget)
import qualified Graphics.UI.Bottle.Widget as Widget
import qualified Graphics.UI.Bottle.Widgets.Box as Box
import qualified Graphics.UI.Bottle.Widgets.Spacer as Spacer
import qualified Graphics.UI.Bottle.Widgets.TextEdit as TextEdit
import           Graphics.UI.Bottle.WidgetsEnvT (runWidgetEnvT)
import qualified Graphics.UI.Bottle.WidgetsEnvT as WE
import           Lamdu.Config (Config)
import qualified Lamdu.Config as Config
import qualified Lamdu.Data.DbLayout as DbLayout
import           Lamdu.Eval.Results (EvalResults)
import qualified Lamdu.Expr.IRef as ExprIRef
import qualified Lamdu.GUI.CodeEdit as CodeEdit
import           Lamdu.GUI.CodeEdit.Settings (Settings(..))
import qualified Lamdu.GUI.VersionControl as VersionControlGUI
import qualified Lamdu.GUI.WidgetIds as WidgetIds
import qualified Lamdu.GUI.Scroll as Scroll
import qualified Lamdu.VersionControl as VersionControl

data Env = Env
    { envEvalRes :: CurAndPrev (EvalResults (ExprIRef.ValI DbLayout.ViewM))
    , envConfig :: Config
    , envSettings :: Settings
    , envStyle :: TextEdit.Style
    , envFullSize :: Widget.Size
    , envCursor :: Widget.Id
    }

make ::
    Env -> Widget.Id ->
    Transaction DbLayout.DbM (Widget (Transaction DbLayout.DbM))
make (Env evalRes config settings style fullSize cursor) rootId =
    do
        actions <- VersionControl.makeActions
        let widgetEnv = WE.Env
                { WE._envCursor = cursor
                , WE._envTextStyle = style
                , WE.backgroundCursorId = WidgetIds.backgroundCursorId
                , WE.cursorBGColor = Config.cursorBGColor config
                , WE.layerCursor = Config.layerCursor $ Config.layers config
                , WE.layerInterval = Config.layerInterval $ Config.layers config
                , WE.verticalSpacing = Config.verticalSpacing config
                , WE.stdSpaceWidth = Config.spaceWidth config
                }
        runWidgetEnvT widgetEnv $
            do
                branchGui <-
                    VersionControlGUI.make (Config.versionControl config)
                    (Config.layerChoiceBG (Config.layers config))
                    id actions $
                    \branchSelector ->
                        do
                            let codeSize = fullSize - Vector2 0 (branchSelector ^. Widget.height)
                            codeEdit <-
                                CodeEdit.make env rootId
                                & WE.mapWidgetEnvT VersionControl.runAction
                                <&> Widget.events %~ VersionControl.runEvent cursor
                            let scrollBox =
                                    Box.vbox [(0.5, hoverPadding), (0.5, codeEdit)]
                                    & Widget.padToSizeAlign codeSize 0
                                    & Scroll.focusAreaIntoWindow fullSize
                                    & Widget.size .~ codeSize
                            Box.vbox [(0.5, scrollBox), (0.5, branchSelector)]
                                & return
                let quitEventMap =
                        Widget.keysEventMap (Config.quitKeys config) (EventMap.Doc ["Quit"]) (error "Quit")
                branchGui
                    & Widget.strongerEvents quitEventMap
                    & return
    where
        hoverPadding = Spacer.makeWidget $ Vector2 0 $ Config.paneHoverPadding $ Config.pane config
        env = CodeEdit.Env
            { CodeEdit.codeProps = DbLayout.codeProps
            , CodeEdit.evalResults = evalRes
            , CodeEdit.config = config
            , CodeEdit.settings = settings
            }
