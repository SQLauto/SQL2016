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
	@PortfolioNameSort=N'Sapphire',
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
    dbcc traceon(2453) with no_infomsgs;

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

    --set @BisId = 1;
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
        InvestmentId        int,
        BasketId            int,
        TaxLotId            int,
        RoleLotId           int,
        TaxLotTypeIsLong    int,
        DenomId             int,
        LocationAccountId   int,
        FinancialAccountId  int,
        InventoryStateId    int,
        StrategyId          int,
        [Net,Book,PeriodEnd,AllAssetsAndPayables,AmortizedCost]         decimal(38,8),
        [Net,Book,PeriodEnd,InDefault,AllAmortizationAssetLiability]    decimal(38,8),
        [Net,Unit,Current,AllAssetsAndPayables,Quantity]                decimal(38,8), --qty
        [Net,Unit,PeriodEnd,InvestmentInMaster,Quantity]                decimal(38,8), --qtySort
        [Net,Book,PeriodEnd,AllAssetsAndPayables,MktValSummary]         decimal(38,8), --mkt val
        [Net,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedPriceGL]     decimal(38,8), --unRealPriceGL
        [Net,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedFXGL]        decimal(38,8), --unRealFXGL
        [Net,Book,PeriodEnd,All,AllAccruedInterest]                     decimal(38,8),
        [Net,Book,PeriodEnd,All,DelayedCompPendingTradeAIRevExp]        decimal(38,8),
        [Net,Book,PeriodEnd,InDefault,AllAccruedInterest]               decimal(38,8),
        [Net,UnitQty,PeriodEnd,AllAssetsAndPayables,Cost]               decimal(38,8),
        [Net,Local,PeriodEnd,CreditActivity,CreditActivity]             decimal(38,8)
    );

    -- Not needed in procedure; could be useful in batch
    --if object_id('tempdb.dbo.#Pos') is not null
    --    exec ('drop table #Pos');
    select top(0) * into #Pos from @Pos;

    insert into @Pos
        exec bis.BalancesSelectAs '#Pos', @BisId, @PeriodStart out, @PeriodEnd out, @PriorKnowledgeDate out, @KnowledgeDate out, null, null, null, 'NonZeroBal,NonZeroAmt';
    
    drop table #Pos;

    declare @Inf table
    (
        InvestmentId        int,
        BasketId            int,
        TaxLotId            int,
        RoleLotId           int,
        TaxLotTypeIsLong    int,
        DenomId             int,
        LocationAccountId   int,
        StrategyId          int,
        [Net,Local,PeriodEnd,Informational,MarketPrice] decimal(38,8), 
        [Net,Local,PeriodEnd,Informational,UnitCost]    decimal(38,8)
    );

    -- Not needed in procedure; could be useful in batch
    --if object_id('tempdb.dbo.#Inf') is not null
    --    exec ('drop table #Inf');
    select top(0) * into #Inf from @Inf;

    insert into @Inf
        exec bis.BalancesSelectAs '#Inf', @BisId, @PeriodStart out, @PeriodEnd out, @PriorKnowledgeDate out, @KnowledgeDate out, null, null, null, '';
    
    drop table #Inf

    select
            CASE TaxLotTypeIsLong WHEN 0 THEN 'Short Positions' ELSE 'Long Positions' END AS LS,
            tl.Invest               Invest,
            tl.InvestCode           InvestCode,
            tl.Group1               Group1,
            tl.Group2               Group2,
            tl.TaxLotDesc,
            tl.LotId                LotID,
            tl.TaxLotDay,
            tl.[Unit Cost]          [CostUnit],
            tl.[Market Price]       [MktPrice],
            SUM(tl.Quantity)        Qty,
            SUM(tl.BookCost)        [CostBook],
            SUM(tl.MktValueBook)    [MVBook],
            SUM(tl.unRealPriceGL)   [UnrealPrice],
            SUM(tl.unRealFXGL)      [UnrealFX],
            SUM(tl.AccruedInt)      [Accrued]
    from
    (
        SELECT
                Pos.TaxLotTypeIsLong,
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
                       WHEN inv.IsCreditFacility = 1 THEN CONCAT(IIF(Basket.IsCreditFacility = 0, 0, IIF([Net,Local,PeriodEnd,CreditActivity,CreditActivity] = 0, 0, ([Net,UnitQty,PeriodEnd,AllAssetsAndPayables,Cost] / [Net,Local,PeriodEnd,CreditActivity,CreditActivity] *100))), ' % of Global Commitment')
                       ELSE ''
                  END AS Desc3, --todo: need to test credit facility. in rsl, it's calling bismgr::getGlobalCommitment() not just balance call!!!

                  IIF(Pos.TaxLotId = 1 OR inv.IsMediumOfExchange = 1 AND Basket.IsForwardFXContract = 0, null, Pos.TaxLotId) AS LotId,
              
                  CASE WHEN portevt.Number = 1 OR inv.IsMediumOfExchange =1 THEN NULL
                       WHEN inv.IsExpenseObligation = 1 AND (finacct.AccountBaseType = 0 OR finacct.AccountBaseType = 1) THEN portevt.TaxLotDate -- BaseType is Asset or Liability
                       ELSE NULL --should call getTaxlLotDate GEN-6128106
                  END AS TaxLotDay,

                  [Net,Unit,Current,AllAssetsAndPayables,Quantity] Quantity,
                  --([Net,Unit,PeriodEnd,AllAssetsAndPayables,Quantity] - [Net,Unit,PeriodEnd,InvestmentInMaster,Quantity]) AS QtySort, don't see this is being used. comment out for now.
                  Inf.[Net,Local,PeriodEnd,Informational,UnitCost] "Unit Cost",
                  Inf.[Net,Local,PeriodEnd,Informational,MarketPrice] AS "Market Price",
                  [Net,Book,PeriodEnd,AllAssetsAndPayables,AmortizedCost] - [Net,Book,PeriodEnd,InDefault,AllAmortizationAssetLiability] "BookCost", --cost book = AmortCost - InDefaultCost
                  [Net,Book,PeriodEnd,AllAssetsAndPayables,MktValSummary] - [Net,Book,PeriodEnd,InDefault,AllAmortizationAssetLiability] "MktValueBook",
                  [Net,Book,PeriodEnd,All,AllAccruedInterest] - [Net,Book,PeriodEnd,All,DelayedCompPendingTradeAIRevExp] - [Net,Book,PeriodEnd,InDefault,AllAccruedInterest] "AccruedInt",
                  IIF(Basket.IsSwapInvestment = 1 AND @LumpSwapGL = 1, [Net,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedPriceGL] + [Net,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedFXGL], [Net,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedPriceGL]) AS "unRealPriceGL",
                  IIF(Basket.IsSwapInvestment = 1 AND @LumpSwapGL = 1, 0, [Net,Book,PeriodEnd,AllAssetsAndPayables,UnrealizedFXGL]) AS "unRealFXGL",

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
           FROM @Pos Pos
           LEFT JOIN @Inf Inf ON Pos.InvestmentId = Inf.InvestmentId AND Pos.BasketId = Inf.BasketId AND Pos.DenomId = Inf.DenomId 
                                            AND Pos.TaxLotId = Inf.TaxLotId AND Pos.RoleLotId = Inf.RoleLotId AND Pos.LocationAccountId = Inf.LocationAccountId
                                            AND Pos.StrategyId = Inf.StrategyId and Pos.TaxLotTypeIsLong = Inf.TaxLotTypeIsLong
           LEFT JOIN aga.Investment inv ON Pos.InvestmentId = inv.Investment_BId
           LEFT JOIN aga.Investment Basket ON Pos.BasketId = Basket.Investment_BId
           LEFT JOIN aga.InvestmentType InvestmentType ON InvestmentType.ChainId = inv.InvestmentType
           LEFT JOIN aga.InvestmentType BasketInvestmentType ON BasketInvestmentType.ChainId = Basket.InvestmentType
           LEFT JOIN aga.MediumOfExchange InvBifurcation ON InvBifurcation.ChainId = inv.BifurcationCurrency
           LEFT JOIN aga.LocationAccount LocationAccount ON Pos.LocationAccountId = LocationAccount.LocationAccount_BId
           LEFT JOIN aga.PortfolioEvent portevt ON cast(Pos.TaxLotId as NVARCHAR(64)) = portevt.Number 
           LEFT JOIN aga.Investment portEvtInv ON portEvtInv.ChainId = portevt.Investment
           LEFT JOIN aga.MediumOfExchange portEvtInvBuyCcy ON portEvtInvBuyCcy.ChainId = portEvtInv.BuyCurrency
           LEFT JOIN aga.MediumOfExchange portEvtInvSellCcy ON portEvtInvSellCcy.ChainId = portEvtInv.SellCurrency
           LEFT JOIN aga.FinancialAccount finacct ON Pos.FinancialAccountId = finacct.FinancialAccount_BId
           LEFT JOIN aga.InventoryState invstate ON Pos.InventoryStateId = invstate.InventoryState_BId
           WHERE
                ((Pos.[Net,Unit,Current,AllAssetsAndPayables,Quantity] !=0 AND (Pos.[Net,Unit,Current,AllAssetsAndPayables,Quantity] >= 0.00001 OR Pos.[Net,Unit,Current,AllAssetsAndPayables,Quantity] <= -0.00001)) AND (IIF(inv.IsExpenseObligation = 1, IIF(finacct.AccountBaseType = 0 OR finacct.AccountBaseType = 1, 'y', 'n'),'n') = 'n') )
                 OR (Pos.[Net,Book,PeriodEnd,All,AllAccruedInterest] != 0)
                 OR ((Pos.[Net,Book,PeriodEnd,AllAssetsAndPayables,AmortizedCost] - Pos.[Net,Book,PeriodEnd,InDefault,AllAmortizationAssetLiability]) != 0 AND (inv.IsExpenseObligation = 1 AND (finacct.AccountBaseType = 0 OR finacct.AccountBaseType = 1)) )

    ) AS tl
    GROUP BY tl.TaxLotTypeIsLong, tl.TaxLotDesc, tl.Desc2, tl.Desc3, tl.TaxLotDay, tl.LotId, tl.CustAccount, tl.Invest, tl.InvestCode, tl.[Unit Cost], tl.[Market Price], tl.Group1, tl.IsMediumOfExchange, tl.IsForwardCash, tl.Group2, tl.OrderDesc
    ORDER BY TaxLotTypeIsLong, tl.Group1, tl.IsMediumOfExchange DESC, tl.IsForwardCash DESC, tl.Group2, tl.Invest, tl.OrderDesc

    dbcc traceoff(2453) with no_infomsgs;
end try
begin catch
    dbcc traceoff(2453) with no_infomsgs;
    throw;
end catch

return 0;
