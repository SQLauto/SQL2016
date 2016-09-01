IF NOT EXISTS (SELECT  schema_name FROM information_schema.schemata WHERE schema_name = 'eisRep')
BEGIN
    EXEC ('CREATE SCHEMA eisRep;')
END

GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'eisRep.taxlotappls') AND type in (N'P'))
DROP PROCEDURE eisRep.taxlotappls
GO
/*	Test execution script
exec eisRep.taxlotappls 
	@PortfolioNameSort=N'Fixed',
	@AccountingParametersCode=N'USD',
	@PeriodStart='1950-01-01 00:00:00',
	@PriorKnowledgeDate='2016-09-01 00:00:01',
	@PeriodEnd='2016-09-01 23:59:59',
	@KnowledgeDate='2016-09-01 23:59:59',

	@LumpSwapGL=0,@Group1=N'LocalBasisCurrency',
	@Group1Field=N'Description',
	@Group2=N'InvestmentType',
	@Group2Field=N'Description'
*/
create procedure eisRep.taxlotappls
    @PortfolioNameSort          nvarchar(400)   = null,
    @AccountingParametersCode   nvarchar(400)   = null,
    @PeriodStart                datetime2(0)    = null,
    @PeriodEnd                  datetime2(0)    = null,
    @PriorKnowledgeDate         datetime2(0)    = null,
    @KnowledgeDate              datetime2(0)    = null,
    @LumpSwapGL                 bit             = null,
    @Group1                     nvarchar(400)   = N'LocalBasisCurrency',
    @Group1Field                nvarchar(400)   = N'Description',
    @Group2                     nvarchar(400)   = N'InvestmentType',
    @Group2Field                nvarchar(400)   = N'Description'
as

set nocount on;

begin try
    dbcc traceon(2453);

    declare
        @Msg nvarchar(4000);

    if @PortfolioNameSort is null
    begin
        set @Msg = N'@PortfolioNameSort must be specified]';
        throw 50000, @Msg, 1;
    end;

    if @AccountingParametersCode is null
    begin
        set @Msg = N'@AccountingParametersCode must be specified]';
        throw 50000, @Msg, 1;
    end;

    if @LumpSwapGL is null
        set @LumpSwapGL = 0;

    declare
        @Now datetime2(0) = sysdatetime();
    declare
    -- This assumes corresponding DB (OS) and AGA TZs; Needs to be made more robust by relying only on AGA TZ
        @EndOfToday datetime2(0) = dateadd(second, -1, cast(dateadd(day, 1, datefromparts(year(@Now), month(@Now), day(@Now))) as datetime2(0)));
    --select @Now, @EndOfToday;

    if @PeriodEnd is null
        set @PeriodEnd = @EndOfToday;

    if @KnowledgeDate is null
        set @KnowledgeDate = @EndOfToday;

    declare
        @KnowledgeDateApprox datetime2(0)   = @KnowledgeDate,
        @IsIncremental bit                  = 1,
        @Tag nvarchar(400)                  = N'',
        @Timeout time(3)                    = '00:01:00',
        @ResultCode tinyint,
        @BisId int;

    declare
        @ResultCode_Success tinyint = 0,
        @ResultCode_UnknownError tinyint = 1,
        @ResultCode_UnknownBis tinyint = 2,
        @ResultCode_Timeout tinyint = 3;

    exec geneva.GetBisIdAtKnowledgeDate
        @KnowledgeDateApprox,
        @IsIncremental,
        @PortfolioNameSort,
        @AccountingParametersCode,
        @Tag,
        @Timeout,
        @ResultCode out,
        @BisId out,
        @KnowledgeDate out;

    --set @BisId = 9;
    --set @ResultCode = @ResultCode_Success;

    if @ResultCode = @ResultCode_UnknownBis
    begin
        set @Msg = N'Cannot find BIS for PortfolioNameSort=[' + @PortfolioNameSort + N'] AccountingParametersCode=[' + @AccountingParametersCode + N']';
        throw 50000, @Msg, 1;
    end;

    if @ResultCode = @ResultCode_UnknownError
    begin
        set @Msg = N'Unknown Error';
        throw 50000, @msg, 1;
    end;

    if @ResultCode = @ResultCode_Timeout
    begin
        set @Msg = N'Timeout while waiting for runs to complete';
        print @Msg;
    end;

    if @ResultCode <> @ResultCode_Success
    begin
        set @Msg = N'Unexpected ResultCode=' + cast(@ResultCode as varchar(10));
        throw 50000, @msg, 1;
    end;

    if @PriorKnowledgeDate is null
        set @PriorKnowledgeDate = @KnowledgeDate;

    --select @PeriodStart PeriodStart, @PeriodEnd PeriodEnd, @PriorKnowledgeDate PriorKnowledgeDate, @KnowledgeDate KnowledgeDate;

    exec aga.SetSessKnowledgeDate @KnowledgeDate;
    exec aga.SetSessEffectiveDate @PeriodEnd;

    declare @Pos table
    (
           InvestmentId         int,
           BasketId             int,
           TaxLotId             int,
           RoleLotId            int,
           TaxLotTypeIsLong     int,
           DenomId              int,
           LocationAccountId    int,
           FinancialAccountId   int,
           InventoryStateId     int,
           StrategyId           int,

           [Long,Book,PeriodEnd,AllAssetsAndPayables,AmortizedCost]         decimal(38,8),
           [Long,Book,PeriodEnd,InDefault,AllAmortizationAssetLiability]    decimal(38,8),
           [Long,Unit,PeriodEnd,AllAssetsAndPayables,Quantity]                decimal(38,8), --qty
           [Long,Unit,PeriodEnd,InvestmentInMaster,Quantity]                decimal(38,8), --qtySort
           --[Long,Local,PeriodEnd,AllAssetsAndPayables,UnitCost] decimal(38,8), --unit cost
           [Long,Book,PeriodEnd,AllAssetsAndPayables,MktValSummary]         decimal(38,8), --mkt val
           [Long,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedPriceGL]     decimal(38,8), --unRealPriceGL
           [Long,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedFXGL]        decimal(38,8), --unRealFXGL
           ----Accrued interest
           [Long,Book,PeriodEnd,All,AllAccruedInterest]                     decimal(38,8),
           [Long,Book,PeriodEnd,All,DelayedCompPendingTradeAIRevExp]        decimal(38,8),
           [Long,Book,PeriodEnd,InDefault,AllAccruedInterest]               decimal(38,8),
           --End Accrued Interest
           [Net,Local,PeriodEnd,OnHandNotational,GlobalFacilityCommitment]  decimal(38,8),
           [Long,UnitQty,PeriodEnd,AllAssetsAndPayables,Cost]               decimal(38,8),
           [Long,Local,PeriodEnd,CreditActivity,CreditActivity]             decimal(38,8),

           [Short,Book,PeriodEnd,AllAssetsAndPayables,AmortizedCost]        decimal(38,8),
           [Short,Book,PeriodEnd,InDefault,AllAmortizationAssetLiability]   decimal(38,8),
           [Short,Unit,PeriodEnd,AllAssetsAndPayables,Quantity]               decimal(38,8), --qty
           [Short,Unit,PeriodEnd,InvestmentInMaster,Quantity]               decimal(38,8), --qtySort
           --[Short,Local,PeriodEnd,AllAssetsAndPayables,UnitCost] decimal(38,8), --unit cost
           [Short,Book,PeriodEnd,AllAssetsAndPayables,MktValSummary]        decimal(38,8), --mkt val
           [Short,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedPriceGL]    decimal(38,8), --unRealPriceGL
           [Short,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedFXGL]       decimal(38,8), --unRealFXGL
           ----Accrued interest
           [Short,Book,PeriodEnd,All,AllAccruedInterest]                    decimal(38,8),
           [Short,Book,PeriodEnd,All,DelayedCompPendingTradeAIRevExp]       decimal(38,8),
           [Short,Book,PeriodEnd,InDefault,AllAccruedInterest]              decimal(38,8),
           --End Accrued Interest
           [Short,UnitQty,PeriodEnd,AllAssetsAndPayables,Cost]              decimal(38,8),
           [Short,Local,PeriodEnd,CreditActivity,CreditActivity]            decimal(38,8)
    );

    declare @b_info table
    (
           InvestmentId         int,
           BasketId             int,
           TaxLotId             int,
           RoleLotId            int,
           TaxLotTypeIsLong     int,
           DenomId              int,
           LocationAccountId    int,
           StrategyId           int,
           [Net,Local,PeriodEnd,Informational,MarketPrice]  decimal(38,8), 
           [Long,Local,PeriodEnd,Informational,UnitCost]    decimal(38,8),
           [Short,Local,PeriodEnd,Informational,UnitCost]   decimal(38,8)
    );

    if object_id('tempdb.dbo.#Pos') is not null
        exec ('drop table #Pos');
    select * into #Pos from @Pos;

    if object_id('tempdb.dbo.#b_info') is not null
        exec ('drop table #b_info');
    select * into #b_info from @b_info;

    insert into @Pos
        exec bis.BalancesSelectAs '#Pos', @BisId, @PeriodStart out, @PeriodEnd out, @PriorKnowledgeDate out, @KnowledgeDate out;

    insert into @b_info
        exec bis.BalancesSelectAs '#b_info', @BisId, @PeriodStart out, @PeriodEnd out, @PriorKnowledgeDate out, @KnowledgeDate out;

    --Long side
    select
		'Long Positions' AS LS,    --     ‘Short positions’ for short
		tl.Invest            AS Invest,
		tl.InvestCode    AS InvestCode,
		tl.Group1            AS Group1,
		tl.Group2            AS Group2,
		tl.TaxLotDesc    AS TaxLotDesc,
		tl.LotId         AS LotID,
		tl.TaxLotDay     AS TaxLotDay,
		tl.[Unit Cost]   AS CostUnit,
		tl.[Market Price] AS MktPrice,
		tl.Desc2             AS Desc2,
		tl.Desc3             AS Desc3,
		tl.IsMediumOfExchange AS IsMediumOfExchange,
		tl.IsForwardCash AS IsForwardCash,
		tl.OrderDesc,
		SUM(tl.Quantity)       AS Qty,
		SUM(tl.BookCost)      AS CostBook,
		SUM(tl.MktValueBook)  AS MVBook,
		SUM(tl.unRealPriceGL) AS UnrealPrice,
		SUM(tl.unRealFXGL)    AS UnrealFX,
		SUM(tl.AccruedInt)    AS Accrued
    from
    (
        SELECT
                  CASE @Group1
                    WHEN 'InvestmentType' THEN IIF(Basket.IsForwardFXContract = 1,[aga].fGetInvestmentTypeCode(Basket.InvestmentType) , InvestmentType.Description)
                    WHEN 'LocalBasisCurrency' THEN InvBifurcation.Description
                    --ELSE Grouping(:Group1, :Group1Field) GEN-6128341
                  END Group1,

                  CASE @Group2
                    WHEN 'InvestmentType' THEN IIF(Basket.IsForwardFXContract = 1, [aga].fGetInvestmentTypeCode(Basket.InvestmentType), InvestmentType.Description)
                    WHEN 'LocalBasisCurrency' THEN InvBifurcation.Description
                    --ELSE Grouping(:Group2, :Group2Field) GEN-6128341
                  END Group2,

                  IIF(Basket.IsForwardFXContract = 1, Basket.Code, inv.Code) InvestCode,

                  CASE WHEN invstate.Code = 'PurchasedAI' OR invstate.Code = 'SoldAI' OR invstate.Code = 'WithheldPurchasedAI' OR invstate.Code = 'WithheldSoldAI'  THEN CONCAT(inv.Code, 'PurchSoldAI')
                       WHEN Basket.IsForwardFXContract = 1 THEN Basket.Code
                       ELSE inv.Code
                  END AS Invest,

                  CASE WHEN inv.IsForwardCash = 1 THEN CONCAT([aga].fGetContractFxRateBifurcationCcy(portevt.ContractFxRateDenominator), 
                                                              [aga].fGetContractFxRateBifurcationCcy(portevt.ContractFxRateNumerator), cast(portEvt.ContractFxRate AS NVARCHAR(64)))
                       WHEN Basket.IsForwardFXContract = 1 THEN CONCAT(portEvtInvBuyCcy.Code, ' per ', portEvtInvSellCcy.Code, ' @ ', cast(portevt.tradeFX AS NVARCHAR(64))) 
                       WHEN inv.IsBond = 1 AND inv.RepoAgreementFlag = 1 THEN CONCAT('Collateral', portEvtInv.Description) --Repo
                       WHEN inv.IsMediumOfExchange = 1 THEN CONCAT(inv.Description, '-', LocationAccount.NameSort, ' ', invstate.Code)
                       WHEN inv.IsContract = 1 AND inv.ForwardPriceInterpolateFlag = 1 THEN CONCAT(inv.Description, ' due ', cast(portevt.ContractExpirationDate AS NVARCHAR(64))) --Commodity
                       WHEN Basket.IsExpenseObligation = 1 THEN finacct.Code
                       ELSE inv.Description
                  END AS TaxLotDesc,

                  CASE WHEN inv.IsBond = 1 OR inv.IsAssetBacked = 1  OR inv.IsOption = 1 OR inv.IsWarrant  = 1 OR inv.IsFuture = 1 OR (inv.IsContract = 1 AND inv.ForwardPriceInterpolateFlag = 1) THEN inv.ExtendedDescription --Bond, AssetBacked, Option, Future, Commodity
                       WHEN inv.IsBond = 1 AND inv.RepoAgreementFlag = 1 THEN portEvtInv.ExtendedDescription --Repo
                       WHEN inv.IsForwardCash = 1 THEN CONCAT(LocationAccount.NameSort, ' - ', cast(portevt.ActualSettleDate AS NVARCHAR(64)))
                       ELSE ''
                  END AS Desc2,

                  CASE WHEN inv.IsBond = 1 AND inv.RepoAgreementFlag = 1 THEN CONCAT('Terms: ', cast(portevt.Coupon AS NVARCHAR(32)), ' Due ', cast(portevt.ActualSettleDate AS NVARCHAR(64)), ' ', LocationAccount.NameSort)
                       WHEN inv.IsCreditFacility = 1 THEN CONCAT(IIF(Basket.IsCreditFacility = 0, 0, ([Long,UnitQty,PeriodEnd,AllAssetsAndPayables,Cost]/ [Long,Local,PeriodEnd,CreditActivity,CreditActivity] *100)), ' % of Global Commitment')
                       ELSE ''
                  END AS Desc3, --todo: need to test credit facility. in rsl, it's calling bismgr::getGlobalCommitment() not just balance call!!!

                  IIF(lp.TaxLotId = 1 OR inv.IsMediumOfExchange = 1 AND Basket.IsForwardFXContract = 0, null, lp.TaxLotId) AS LotId,
              
                  CASE WHEN portevt.Number = 1 OR inv.IsMediumOfExchange =1 THEN NULL
                       WHEN inv.IsExpenseObligation = 1 AND (finacct.AccountBaseType = 0 OR finacct.AccountBaseType = 1) THEN portevt.TaxLotDate -- BaseType is Asset or Liability
                       ELSE NULL --should call getTaxlLotDate GEN-6128106
                  END AS TaxLotDay,

                  [Long,Unit,PeriodEnd,AllAssetsAndPayables,Quantity] Quantity,
                  --([Long,Unit,PeriodEnd,AllAssetsAndPayables,Quantity] - [Long,Unit,PeriodEnd,InvestmentInMaster,Quantity]) AS QtySort, don't see this is being used. comment out for now.
                  b_info.[Long,Local,PeriodEnd,Informational,UnitCost] "Unit Cost",
                  b_info.[Net,Local,PeriodEnd,Informational,MarketPrice] AS "Market Price",
                  [Long,Book,PeriodEnd,AllAssetsAndPayables,AmortizedCost] - [Long,Book,PeriodEnd,InDefault,AllAmortizationAssetLiability] "BookCost", --cost book = AmortCost - InDefaultCost
                  [Long,Book,PeriodEnd,AllAssetsAndPayables,MktValSummary] - [Long,Book,PeriodEnd,InDefault,AllAmortizationAssetLiability] "MktValueBook",
                  [Long,Book,PeriodEnd,All,AllAccruedInterest] - [Long,Book,PeriodEnd,All,DelayedCompPendingTradeAIRevExp] - [Long,Book,PeriodEnd,InDefault,AllAccruedInterest] "AccruedInt",
                  IIF(Basket.IsSwapInvestment = 1 AND @LumpSwapGL = 1, [Long,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedPriceGL] + [Long,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedFXGL], [Long,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedPriceGL]) AS "unRealPriceGL",
                  IIF(Basket.IsSwapInvestment = 1 AND @LumpSwapGL = 1, 0, [Long,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedFXGL]) AS "unRealFXGL",

                  CASE WHEN inv.IsForwardCash = 1  THEN CONCAT(
                        [aga].fGetContractFxRateBifurcationCcy(portevt.ContractFxRateDenominator)
                        , [aga].fGetContractFxRateBifurcationCcy(portevt.ContractFxRateNumerator), cast(portevt.SettleDate AS NVARCHAR(64)), LocationAccount.NameSort, cast(portevt.EventDate AS NVARCHAR(64)))
                       WHEN Basket.IsForwardFXContract = 1 THEN CONCAT(portEvtInvBuyCcy.Code, portEvtInvSellCcy.Code, portevt.ActualSettleDate, LocationAccount.NameSort, portevt.EventDate)
                       --below same as taxlotdesc column
                       WHEN inv.IsBond = 1 AND inv.RepoAgreementFlag = 1 THEN CONCAT('Collateral', portEvtInv.Description) --Repo
                       WHEN inv.IsMediumOfExchange = 1 THEN CONCAT(inv.Description, '-', LocationAccount.NameSort, ' ', invstate.Code)
                       WHEN inv.IsContract = 1 AND inv.ForwardPriceInterpolateFlag = 1 THEN CONCAT(inv.Description, ' due ', cast(portevt.ContractExpirationDate AS NVARCHAR(64))) --Commodity
                       WHEN Basket.IsExpenseObligation = 1 THEN finacct.Code
                       ELSE inv.Description
                  END AS OrderDesc,

                  LocationAccount.NameSort CustAccount,
                  inv.Description,
                  --For SSRS
                  inv.IsMediumOfExchange IsMediumOfExchange,
                  inv.IsForwardCash      IsForwardCash,
                  IIF(inv.IsExpenseObligation = 1, IIF(finacct.AccountBaseType = 0 OR finacct.AccountBaseType = 1, 'y', 'n'),'n') AS IsEOAndIsAssetORLiability --0 is Asset; 1 is Liability    
           FROM @Pos lp
           LEFT JOIN @b_info b_info ON lp.InvestmentId = b_info.InvestmentId AND lp.BasketId = b_info.BasketId AND lp.DenomId = b_info.DenomId 
                                            AND lp.TaxLotId = b_info.TaxLotId AND lp.RoleLotId = b_info.RoleLotId AND lp.LocationAccountId = b_info.LocationAccountId
                                            AND lp.StrategyId = b_info.StrategyId
           LEFT JOIN aga.Investment inv ON lp.InvestmentId = inv.Investment_BId
           LEFT JOIN aga.Investment Basket ON lp.BasketId = Basket.Investment_BId
           LEFT JOIN aga.InvestmentType InvestmentType ON InvestmentType.ChainId = inv.InvestmentType
           LEFT JOIN aga.InvestmentType BasketInvestmentType ON BasketInvestmentType.ChainId = Basket.InvestmentType
           LEFT JOIN aga.MediumOfExchange InvBifurcation ON InvBifurcation.ChainId = inv.BifurcationCurrency
           LEFT JOIN aga.LocationAccount LocationAccount ON lp.LocationAccountId = LocationAccount.LocationAccount_BId
           LEFT JOIN aga.PortfolioEvent portevt ON cast(lp.TaxLotId as NVARCHAR(64)) = portevt.Number 
           LEFT JOIN aga.Investment portEvtInv ON portEvtInv.ChainId = portevt.Investment
           LEFT JOIN aga.MediumOfExchange portEvtInvBuyCcy ON portEvtInvBuyCcy.ChainId = portEvtInv.BuyCurrency
           LEFT JOIN aga.MediumOfExchange portEvtInvSellCcy ON portEvtInvSellCcy.ChainId = portEvtInv.SellCurrency
           LEFT JOIN aga.FinancialAccount finacct ON lp.FinancialAccountId = finacct.FinancialAccount_BId
           LEFT JOIN aga.InventoryState invstate ON lp.InventoryStateId = invstate.InventoryState_BId
           WHERE ( ([lp].[Long,Unit,PeriodEnd,AllAssetsAndPayables,Quantity] !=0 AND ( [lp].[Long,Unit,PeriodEnd,AllAssetsAndPayables,Quantity] >= 0.00001 OR [lp].[Long,Unit,PeriodEnd,AllAssetsAndPayables,Quantity] <= -0.00001)) AND (IIF(inv.IsExpenseObligation = 1, IIF(finacct.AccountBaseType = 0 OR finacct.AccountBaseType = 1, 'y', 'n'),'n') = 'n') )
                 OR ([lp].[Long,Book,PeriodEnd,All,AllAccruedInterest] != 0)
                 OR ( ([lp].[Long,Book,PeriodEnd,AllAssetsAndPayables,AmortizedCost] - [lp].[Long,Book,PeriodEnd,InDefault,AllAmortizationAssetLiability]) != 0 AND (inv.IsExpenseObligation = 1 AND (finacct.AccountBaseType = 0 OR finacct.AccountBaseType = 1)) )

    ) AS tl
    GROUP BY tl.TaxLotDesc, tl.Desc2, tl.Desc3, tl.TaxLotDay, tl.LotId, tl.CustAccount, tl.Invest, tl.InvestCode, tl.[Unit Cost], tl.[Market Price], tl.Group1, tl.IsMediumOfExchange, tl.IsForwardCash, tl.Group2, tl.OrderDesc
    --ORDER BY  tl.Group1, tl.IsMediumOfExchange DESC, tl.IsForwardCash DESC, tl.Group2, tl.Invest, tl.OrderDesc

union all

    --Short side
    select
		'Short Positions' AS LS,
		tl.Invest		 AS Invest,
		tl.InvestCode    AS InvestCode,
		tl.Group1		 AS Group1,
		tl.Group2		 AS Group2,
		tl.TaxLotDesc    AS TaxlotDescription,
		tl.LotId         AS TaxLotID,
		tl.TaxLotDay     AS [Lot Date],
		tl.[Unit Cost]   AS [Unit Cost],
		tl.[Market Price] AS [Market price],
		tl.Desc2		 AS Desc2,
		tl.Desc3		 AS Desc3,
		tl.IsMediumOfExchange AS IsMediumOfExchange,
		tl.IsForwardCash AS IsForwardCash,
		tl.OrderDesc,
		SUM(tl.Quantity)	  AS Quantity,
		SUM(tl.BookCost)      AS [Cost Book],
		SUM(tl.MktValueBook)  AS [Market Value Book],
		SUM(tl.unRealPriceGL) AS [Price Gain/Loss],
		SUM(tl.unRealFXGL)    AS [FX Gain/Loss],
		SUM(tl.AccruedInt)    AS [Accrued Interest]
    from
    (
        select
                  CASE @Group1
                    WHEN 'InvestmentType' THEN IIF(Basket.IsForwardFXContract = 1,[aga].fGetInvestmentTypeCode(Basket.InvestmentType) , InvestmentType.Description)
                    WHEN 'LocalBasisCurrency' THEN InvBifurcation.Description
                    --ELSE Grouping(:Group1, :Group1Field) GEN-6128341
                  END Group1,

                  CASE @Group2
                    WHEN 'InvestmentType' THEN IIF(Basket.IsForwardFXContract = 1, [aga].fGetInvestmentTypeCode(Basket.InvestmentType), InvestmentType.Description)
                    WHEN 'LocalBasisCurrency' THEN InvBifurcation.Description
                    --ELSE Grouping(:Group2, :Group2Field) GEN-6128341
                  END Group2,

                  IIF(Basket.IsForwardFXContract = 1, Basket.Code, inv.Code) InvestCode,

                  CASE WHEN invstate.Code = 'PurchasedAI' OR invstate.Code = 'SoldAI' OR invstate.Code = 'WithheldPurchasedAI' OR invstate.Code = 'WithheldSoldAI'  THEN CONCAT(inv.Code, 'PurchSoldAI')
                       WHEN Basket.IsForwardFXContract = 1 THEN Basket.Code
                       ELSE inv.Code
                  END AS Invest,

                  CASE WHEN inv.IsForwardCash = 1 THEN CONCAT([aga].fGetContractFxRateBifurcationCcy(portevt.ContractFxRateDenominator), 
                                                              [aga].fGetContractFxRateBifurcationCcy(portevt.ContractFxRateNumerator), cast(portEvt.ContractFxRate AS NVARCHAR(64)))
                       WHEN Basket.IsForwardFXContract = 1 THEN CONCAT(portEvtInvBuyCcy.Code, ' per ', portEvtInvSellCcy.Code, ' @ ', cast(portevt.tradeFX AS NVARCHAR(64))) 
                       WHEN inv.IsBond = 1 AND inv.RepoAgreementFlag = 1 THEN CONCAT('Collateral', portEvtInv.Description) --Repo
                       WHEN inv.IsMediumOfExchange = 1 THEN CONCAT(inv.Description, '-', LocationAccount.NameSort, ' ', invstate.Code)
                       WHEN inv.IsContract = 1 AND inv.ForwardPriceInterpolateFlag = 1 THEN CONCAT(inv.Description, ' due ', cast(portevt.ContractExpirationDate AS NVARCHAR(64))) --Commodity
                       WHEN Basket.IsExpenseObligation = 1 THEN finacct.Code
                       ELSE inv.Description
                  END AS TaxLotDesc,

                  CASE WHEN inv.IsBond = 1 OR inv.IsAssetBacked = 1  OR inv.IsOption = 1 OR inv.IsWarrant  = 1 OR inv.IsFuture = 1 OR (inv.IsContract = 1 AND inv.ForwardPriceInterpolateFlag = 1) THEN inv.ExtendedDescription --Bond, AssetBacked, Option, Future, Commodity
                       WHEN inv.IsBond = 1 AND inv.RepoAgreementFlag = 1 THEN portEvtInv.ExtendedDescription --Repo
                       WHEN inv.IsForwardCash = 1 THEN CONCAT(LocationAccount.NameSort, ' - ', cast(portevt.ActualSettleDate AS NVARCHAR(64)))
                       ELSE ''
                  END AS Desc2,

                  CASE WHEN inv.IsBond = 1 AND inv.RepoAgreementFlag = 1 THEN CONCAT('Terms: ', cast(portevt.Coupon AS NVARCHAR(32)), ' Due ', cast(portevt.ActualSettleDate AS NVARCHAR(64)), ' ', LocationAccount.NameSort)
                       WHEN inv.IsCreditFacility = 1 THEN CONCAT(IIF(Basket.IsCreditFacility = 0, 0, ([Short,UnitQty,PeriodEnd,AllAssetsAndPayables,Cost]/ [Short,Local,PeriodEnd,CreditActivity,CreditActivity] *100)), ' % of Global Commitment')
                       ELSE ''
                  END AS Desc3, --todo: need to test credit facility. in rsl, it's calling bismgr::getGlobalCommitment() not just balance call!!!

                  IIF(sp.TaxLotId = 1 OR inv.IsMediumOfExchange = 1 AND Basket.IsForwardFXContract = 0, null, sp.TaxLotId) AS LotId,
              
                  CASE WHEN portevt.Number = 1 OR inv.IsMediumOfExchange =1 THEN NULL
                       WHEN finacct.AccountBaseType = 0 OR finacct.AccountBaseType = 1 THEN portevt.TaxLotDate
                       ELSE NULL --should call getTaxlLotDate GEN-6128106
                  END AS TaxLotDay,

                  [Short,Unit,PeriodEnd,AllAssetsAndPayables,Quantity] Quantity,
                  --([Short,Unit,PeriodEnd,AllAssetsAndPayables,Quantity] - [Short,Unit,PeriodEnd,InvestmentInMaster,Quantity]) AS QtySort, don't see this is being used. comment out for now.
                  b_info.[Short,Local,PeriodEnd,Informational,UnitCost] "Unit Cost",
                  b_info.[Net,Local,PeriodEnd,Informational,MarketPrice] AS "Market Price",
                  [Short,Book,PeriodEnd,AllAssetsAndPayables,AmortizedCost] - [Short,Book,PeriodEnd,InDefault,AllAmortizationAssetLiability] "BookCost", --cost book = AmortCost - InDefaultCost
                  [Short,Book,PeriodEnd,AllAssetsAndPayables,MktValSummary] - [Short,Book,PeriodEnd,InDefault,AllAmortizationAssetLiability] "MktValueBook",
                  [Short,Book,PeriodEnd,All,AllAccruedInterest] - [Short,Book,PeriodEnd,All,DelayedCompPendingTradeAIRevExp] - [Short,Book,PeriodEnd,InDefault,AllAccruedInterest] "AccruedInt",
                  IIF(Basket.IsSwapInvestment = 1 AND @LumpSwapGL = 1, [Short,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedPriceGL] + [Short,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedFXGL], [Short,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedPriceGL]) AS "unRealPriceGL",
                  IIF(Basket.IsSwapInvestment = 1 AND @LumpSwapGL = 1, 0, [Short,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedFXGL]) AS "unRealFXGL",

                  CASE WHEN inv.IsForwardCash = 1  THEN CONCAT(
                        [aga].fGetContractFxRateBifurcationCcy(portevt.ContractFxRateDenominator)
                        , [aga].fGetContractFxRateBifurcationCcy(portevt.ContractFxRateNumerator), cast(portevt.SettleDate AS NVARCHAR(64)), LocationAccount.NameSort, cast(portevt.EventDate AS NVARCHAR(64)))
                       WHEN Basket.IsForwardFXContract = 1 THEN CONCAT(portEvtInvBuyCcy.Code, portEvtInvSellCcy.Code, portevt.ActualSettleDate, LocationAccount.NameSort, portevt.EventDate)
                       --below same as taxlotdesc column
                       WHEN inv.IsBond = 1 AND inv.RepoAgreementFlag = 1 THEN CONCAT('Collateral', portEvtInv.Description) --Repo
                       WHEN inv.IsMediumOfExchange = 1 THEN CONCAT(inv.Description, '-', LocationAccount.NameSort, ' ', invstate.Code)
                       WHEN inv.IsContract = 1 AND inv.ForwardPriceInterpolateFlag = 1 THEN CONCAT(inv.Description, ' due ', cast(portevt.ContractExpirationDate AS NVARCHAR(64))) --Commodity
                       WHEN Basket.IsExpenseObligation = 1 THEN finacct.Code
                       ELSE inv.Description
                  END AS OrderDesc,

                  LocationAccount.NameSort CustAccount,
                  inv.Description,
                  --For SSRS
                  inv.IsMediumOfExchange IsMediumOfExchange,
                  inv.IsForwardCash      IsForwardCash,
                  IIF(inv.IsExpenseObligation = 1, IIF(finacct.AccountBaseType = 0 OR finacct.AccountBaseType = 1, 'y', 'n'),'n') AS IsEOAndIsAssetORLiability --0 is Asset; 1 is Liability    
           FROM @Pos sp
           LEFT JOIN @b_info b_info ON sp.InvestmentId = b_info.InvestmentId AND sp.BasketId = b_info.BasketId AND sp.DenomId = b_info.DenomId 
                                            AND sp.TaxLotId = b_info.TaxLotId AND sp.RoleLotId = b_info.RoleLotId AND sp.LocationAccountId = b_info.LocationAccountId
                                            AND sp.StrategyId = b_info.StrategyId
           LEFT JOIN aga.Investment inv ON sp.InvestmentId = inv.Investment_BId
           LEFT JOIN aga.Investment Basket ON sp.BasketId = Basket.Investment_BId
           LEFT JOIN aga.InvestmentType InvestmentType ON InvestmentType.ChainId = inv.InvestmentType
           LEFT JOIN aga.InvestmentType BasketInvestmentType ON BasketInvestmentType.ChainId = Basket.InvestmentType
           LEFT JOIN aga.MediumOfExchange InvBifurcation ON InvBifurcation.ChainId = inv.BifurcationCurrency
           LEFT JOIN aga.LocationAccount LocationAccount ON sp.LocationAccountId = LocationAccount.LocationAccount_BId
           LEFT JOIN aga.PortfolioEvent portevt ON cast(sp.TaxLotId as NVARCHAR(64)) = portevt.Number 
           LEFT JOIN aga.Investment portEvtInv ON portEvtInv.ChainId = portevt.Investment
           LEFT JOIN aga.MediumOfExchange portEvtInvBuyCcy ON portEvtInvBuyCcy.ChainId = portEvtInv.BuyCurrency
           LEFT JOIN aga.MediumOfExchange portEvtInvSellCcy ON portEvtInvSellCcy.ChainId = portEvtInv.SellCurrency
           LEFT JOIN aga.FinancialAccount finacct ON sp.FinancialAccountId = finacct.FinancialAccount_BId
           LEFT JOIN aga.InventoryState invstate ON sp.InventoryStateId = invstate.InventoryState_BId
           WHERE ( ([sp].[Short,Unit,PeriodEnd,AllAssetsAndPayables,Quantity] !=0 AND ( [sp].[Short,Unit,PeriodEnd,AllAssetsAndPayables,Quantity] >= 0.00001 OR [sp].[Short,Unit,PeriodEnd,AllAssetsAndPayables,Quantity] <= -0.00001)) AND (IIF(inv.IsExpenseObligation = 1, IIF(finacct.AccountBaseType = 0 OR finacct.AccountBaseType = 1, 'y', 'n'),'n') = 'n') )
                 OR ([sp].[Short,Book,PeriodEnd,All,AllAccruedInterest] != 0)
                 OR ( ([sp].[Short,Book,PeriodEnd,AllAssetsAndPayables,AmortizedCost] - [sp].[Short,Book,PeriodEnd,InDefault,AllAmortizationAssetLiability]) != 0 AND (inv.IsExpenseObligation = 1 AND (finacct.AccountBaseType = 0 OR finacct.AccountBaseType = 1)) )

    ) AS tl
    GROUP BY tl.TaxLotDesc, tl.Desc2, tl.Desc3, tl.TaxLotDay, tl.LotId, tl.CustAccount, tl.Invest, tl.InvestCode, tl.[Unit Cost], tl.[Market Price], tl.Group1, tl.IsMediumOfExchange, tl.IsForwardCash, tl.Group2, tl.OrderDesc
    --ORDER BY  tl.Group1, tl.IsMediumOfExchange DESC, tl.IsForwardCash DESC, tl.Group2, tl.Invest, tl.OrderDesc

    dbcc traceoff(2453);
end try
begin catch
    dbcc traceoff(2453);
    throw;
end catch

return 0;
