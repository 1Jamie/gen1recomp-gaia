return function(V)
  local sym = V.sym

  -- pokeemerald/src/data/trade.h:624
  V.TRADE_POKEBALL_PAL = sym("trade.o:sPokeball_Pal")
  V.TRADE_POKEBALL_GFX = sym("trade.o:sPokeball_Gfx")
  V.TRADE_CABLE_CLOSEUP_MAP = sym("trade.o:sCableCloseup_Map")
  V.TRADE_GBA_PAL = sym("trade.o:sGba_Pal")
  V.TRADE_LINK_MON_PAL = sym("trade.o:sLinkMon_Pal")
  V.TRADE_LINK_MON_GLOW_GFX = sym("trade.o:sLinkMonGlow_Gfx")
  V.TRADE_LINK_MON_SHADOW_GFX = sym("trade.o:sLinkMonShadow_Gfx")
  V.TRADE_CABLE_END_GFX = sym("trade.o:sCableEnd_Gfx")
  V.TRADE_GBA_SCREEN_GFX = sym("trade.o:sGbaScreen_Gfx")
  V.TRADE_GBA_MAP_WIRELESS = sym("trade.o:sGbaMapWireless")
  V.TRADE_GBA_MAP_CABLE = sym("trade.o:sGbaMapCable")
  -- pokeemerald/src/trade.c:3178
  V.TRADE_MON_SHADOW_MAP = sym("gTradePlatform_Tilemap")
  -- pokeemerald/src/data/trade.h:907
  V.TRADE_GBA_SCREEN_ANIM = sym("trade.o:sAnim_GbaScreen_Long")
  -- pokeemerald/src/data/trade.h:27
  V.TRADE_MOVES_BOX_MAP = sym("trade.o:sTradeMovesBoxTilemap")
  V.TRADE_PARTY_BOX_MAP = sym("trade.o:sTradePartyBoxTilemap")
  V.TRADE_STRIPES_BG2_MAP = sym("trade.o:sTradeStripesBG2Tilemap")
  V.TRADE_STRIPES_BG3_MAP = sym("trade.o:sTradeStripesBG3Tilemap")
  -- pokeemerald/src/graphics.c:1457
  V.TRADE_GBA_GFX = sym("gTradeGba_Gfx")
  V.TRADE_GBA_PAL2 = sym("gTradeGba2_Pal")
  V.TRADE_MENU_PAL = sym("gTradeMenu_Pal")
  V.TRADE_CURSOR_PAL = sym("gTradeCursor_Pal")
  V.TRADE_MENU_GFX = sym("gTradeMenu_Gfx")
  V.TRADE_CURSOR_GFX = sym("gTradeCursor_Gfx")
  V.TRADE_MENU_MAP = sym("gTradeMenu_Tilemap")
  V.TRADE_MENU_MON_BOX_MAP = sym("gTradeMenuMonBox_Tilemap")
end
