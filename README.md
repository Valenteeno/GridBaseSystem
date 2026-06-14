# GridBaseSystem

Grid-based trading system (V2 current; earlier grid builds archived).

> **Proprietary software** — © Teenodi Ltd. All rights reserved. Private repository; not for distribution. See [LICENSE](LICENSE).

## Grid-Base_System_V2.mq5

### Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `Username` | string | `""` | Enter your username |

*Grid Base System*

| Input | Type | Default | Description |
|---|---|---|---|
| `InstrumentStartPoint` | double | `5553.01` |  |
| `TradeDirection` | TradeDirectionEnum | `BOTH` |  |
| `MaxBuyPositions` | int | `10` |  |
| `MaxSellPositions` | int | `10` |  |
| `GridSize` | double | `50` |  |
| `ReopenPosition` | YesNoEnum | `YES` |  |

*Moving Average Filter & Reverse Stop*

| Input | Type | Default | Description |
|---|---|---|---|
| `MAFilterPeriod` | int | `45` | MA Period for filter and reverse stop |
| `EnableReverseMA` | YesNoEnum | `YES` | Enable MA Reverse Stop |

*Lot Management*

| Input | Type | Default | Description |
|---|---|---|---|
| `LotSizingMethod` | LotSizingType | `FIXED` |  |
| `FixedLot` | double | `0.01` |  |
| `MultipleLot` | double | `2` |  |
| `PlusLot` | double | `0.01` |  |
| `MAX_BUY_LOT` | double | `5.0` |  |
| `MAX_SELL_LOT` | double | `5.0` |  |

*Take Profit Management*

| Input | Type | Default | Description |
|---|---|---|---|
| `TP` | double | `200` |  |
| `TPType` | TPTypeEnum | `INDIVIDUAL_TP` |  |

*Stoploss Management*

| Input | Type | Default | Description |
|---|---|---|---|
| `SL` | double | `100` |  |

## Archive

Earlier versions / forks are preserved under [`archive/`](archive/) for reference.

## Install

1. Copy the source file(s) into your MetaTrader 5 `MQL5/` tree (`Experts/`, `Indicators/`, or `Scripts/` as appropriate).
2. In MetaEditor, open the file and compile (**F7**).
3. Attach the compiled program to a chart from the terminal Navigator.

## License

Proprietary and confidential. © Teenodi Ltd. All rights reserved. See [LICENSE](LICENSE).
