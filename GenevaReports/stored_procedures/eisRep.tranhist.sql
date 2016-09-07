IF NOT EXISTS (SELECT  schema_name FROM information_schema.schemata WHERE schema_name = 'eisRep')
BEGIN
    EXEC ('CREATE SCHEMA eisRep;')
END

GO

IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'eisRep.TranHist') AND type in (N'P'))
DROP PROCEDURE eisRep.TranHist
GO

IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'eisRep.TranHist') AND type in (N'P'))
DROP PROCEDURE eisRep.TranHist
GO
/*	Test execution script
exec eisRep.TranHist @PortfolioNameSort=N'Global13030',@AccountingParametersCode=N'USDfx',@PeriodStart='2009-08-01 00:00:00',@PriorKnowledgeDate=NULL,@PeriodEnd='2009-08-09 23:59:59',@KnowledgeDate='2016-09-07 23:59:59',@SettleCurrency=N'',@Group1=N'LocalBasisCurrency',@EventType=N'',@Group1Field=N'Description',@BookCurrency=NULL,@Group2=N'InvestmentType',@Group2Field=N'Description'
*/
create procedure eisRep.TranHist
    @PortfolioNameSort          nvarchar(400)   = null,
    @AccountingParametersCode   nvarchar(400)   = null,
    @PeriodStart                datetime2(0)    = null,
    @PeriodEnd                  datetime2(0)    = null,
    @PriorKnowledgeDate         datetime2(0)    = null,
    @KnowledgeDate              datetime2(0)    = null,
	@SettleCurrency				nvarchar(64) = N'',
	@EventType					nvarchar(256) = N'',
	@BookCurrency				nvarchar(400) = N'',
    @Group1                     nvarchar(400)   = N'LocalBasisCurrency',
    @Group1Field                nvarchar(400)   = N'Description',
    @Group2                     nvarchar(400)   = N'InvestmentType',
    @Group2Field                nvarchar(400)   = N'Description'
as
begin

declare @Msg nvarchar(4000);

exec aga.SetSessKnowledgeDate @KnowledgeDate;
--select @PeriodStart PS, @PeriodEnd PE, @KnowledgeDate K, aga.GetSessKnowledgeDate();
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
    @BisId int

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

declare @PortfolioId int = null

if object_id('tempdb.dbo.#tjel') is not null
       exec ('drop table #tjel');

set nocount on;

create table #tjel
(
	TDate	datetime2(7),
	Settle	datetime2(0),
	SDate	datetime2(0),
	AccountingDate datetime2(0),
	EventType nvarchar(255),
	EType	nvarchar(max),
	GroupByTranID	int,
	RealTranID		int,
	Invest	nvarchar(max),
	ICode	nvarchar(400),
	LocalAmount	decimal(38,8),
	BookAmount	decimal(38,8),
	QuantityAmount	decimal(38,8),
	InvestmentId	int,
	BasketId	int,
	StrategyId	int,
	DenomId		int,
	FinancialAccountId	int,
	InventoryStateId	int,
	LocationAccountId	int,
	TaxLotId	int,
	DescriptionId	tinyint,
	SCurrency	nvarchar(400),
	AccountDate	datetime2(0),
	PershareAmt	float,
	MedofExch	bit,
	RDate		datetime2(7),
	RealID		nvarchar(400),
	WithholdCheck	bit, 
	PETaxLotId	int
);

if object_id('tempdb.dbo.#tjel2') is not null
       exec ('drop table #tjel2');

create table #tjel2
(
	TDate	datetime2(7),
	Settle  datetime2(0),
	SDate	datetime2(0),
	EType	nvarchar(max),
	EventType nvarchar(255),
	GroupByTranID	int,
	RealTranID		int,
	EventID	nvarchar(128),
	EventIDLink	nvarchar(128),
	ICode	nvarchar(400),
	QuantityAmount	decimal(38,8),
	Price	float,
	Invest	nvarchar(max),
	SCurrency	nvarchar(400),
	LocalGain	decimal(38,8),
	BookGain	decimal(38,8),
	AccountDate	datetime2(0),
	PershareAmt	float,
	DenomId		int,
	StrategyId	int,
	MedofExch	bit,
	RDate		datetime2(7),
	RealID		nvarchar(400),
	WithholdCheck	bit,
	LocationAccountId	int,
	InventoryStateId	int,
	PETaxLotId	int,
	TaxLotId	int,
	LocalAmount	decimal(38,8),
	BookAmount	decimal(38,8)
);


if object_id('tempdb.dbo.#troutine') is not null
       exec ('drop table #troutine');

create table #troutine
(
	EventID	nvarchar(128),
	EventIDLink	nvarchar(128),
	TDate	datetime2(7),
	SDate	datetime2(0),
	Invest	nvarchar(max),
	LocationAccountId	int,
	DenomId		int,
	Quantity	decimal(38,8),
	LocalGain	decimal(38,8), 
	BookGain	decimal(38,8), 
	LocalNet	decimal(38,8), 
	BookNet		decimal(38,8),
	Price		float,
	PETaxLotId	int,
	RDate		datetime2(7),
	PerShareAmt	decimal(38,8),
	SCurrency	nvarchar(400),
	EType	nvarchar(max),
	EventType nvarchar(255),
);

if object_id('tempdb.dbo.#tprint') is not null
       exec ('drop table #tprint');

create table #tprint
(
	EventID	nvarchar(128),
	EventIDLink	nvarchar(128),
	TDate	datetime2(7),
	SDate	datetime2(0),
	Invest	nvarchar(max),
	Quantity	decimal(38,8),
	LocalGain	decimal(38,8), 
	BookGain	decimal(38,8), 
	LocalNet	decimal(38,8), 
	BookNet		decimal(38,8),
	Price		float,
	PETaxLotId	int,
	RDate		datetime2(7),
	SCurrency	nvarchar(400),
	EType	nvarchar(max), 
	EventType nvarchar(255),
	Custodian nvarchar(400)
);


if @BisId is null
begin
       set @msg  = N'Cannot find any BIS for Portfolio [' + @PortfolioNameSort + N']';
       throw 50000, @msg, 1
end;


declare @AllRevExpID int = null;
SELECT @AllRevExpID = f.InstanceId FROM aga.FinancialAccount f where f.Code = N'AllRevenuesAndExpenses'

INSERT INTO #tjel
(
	TDate, Settle, SDate, EventType, EType, GroupByTranID, RealTranID, Invest, ICode, LocalAmount, BookAmount, QuantityAmount, AccountingDate, InvestmentId, BasketId, StrategyId,
	DenomId, FinancialAccountId, InventoryStateId, LocationAccountId, TaxLotId, PETaxLotId, DescriptionId, SCurrency, AccountDate, PershareAmt, MedofExch, RDate, RealID, WithholdCheck
)
SELECT 

	CASE WHEN jel.AccountingDate = cast(portevt.ReinvestDate AS DATETIME2(2)) THEN  cast(portevt.ReinvestDate AS DATETIME2(2))
		 WHEN portevt.IsCDXCreditEvent = 1	THEN portevt.AuctionDate
		 ELSE ISNULL(portevt.EventDate, portevt.EventDate) END TDate, --TODO: AdjustedEvent

	CASE WHEN jel.AccountingDate = CAST(portevt.ReinvestDate AS DATETIME2(2)) THEN cast(portevt.ReinvestDate AS DATETIME2(2))
		 WHEN CONVERT(date, portevt.SettleDate) = N'1901-01-01' THEN IIF(portevt.IsCDXCreditEvent = 1, portevt.AuctionDate, ISNULL(portevt.EventDate, portevt.EventDate))
		 WHEN (SELECT b.IsCreditFacility FROM aga.Investment b WHERE b.Investment_BId = jel.BasketId) = 1 THEN portevt.ActualSettleDate
		 ELSE portevt.SettleDate END AS Settle,

	CASE WHEN portevt.IsRepo = 1 OR portevt.IsReverseRepo = 1 THEN portevt.ActualSettleDate
		 WHEN jel.AccountingDate =  cast(portevt.ReinvestDate AS DATETIME2(2)) THEN cast(portevt.ReinvestDate AS DATETIME2(2))
		 WHEN CONVERT(date, portevt.SettleDate) = N'1901-01-01' THEN IIF(portevt.IsCDXCreditEvent = 1, portevt.AuctionDate, ISNULL(portevt.EventDate, portevt.EventDate))
		 WHEN (SELECT b.IsCreditFacility FROM aga.Investment b WHERE b.Investment_BId = jel.BasketId) = 1 THEN portevt.ActualSettleDate
		 ELSE portevt.SettleDate END AS SDate,
	cl.ClassName EventType,
	-- portevet.eventType GEN-6128879
	CASE WHEN aga.fgetFinAcctCode(jel.FinancialAccountId) IN (N'interestReclaimTaxReceipt', N'Reclaim', N'DividendReclaimTaxReceipt', N'InterestWithholdingTaxExpense', N'Withholding', N'DividendWithholdingTaxExpense')
			  THEN ISNULL( (SELECT et.Description FROM aga.EventsType et WHERE portevt.EventDesc = et.ChainId), N'EventType')
		 ELSE N'' END AS EType,

	CASE WHEN jel.AccountingDate = portevt.ReinvestDate THEN NULL
		 ELSE jel.PETaxLotId END AS GroupByTranID,

	CASE WHEN jel.AccountingDate = CAST(portevt.ReinvestDate AS DATETIME2(7)) THEN NULL
		 WHEN portevt.IsStockLoanActivity = 1 THEN portevt.Number
		 ELSE jel.PETaxLotId END AS RealTranID,

	CASE WHEN portevt.IsDividend = 1 THEN IIF( portevt.ReinvestFlag = 1 AND jel.AccountingDate = cast(portevt.ReinvestDate AS DATETIME2(2)), inv.Description, portevtinv.Description)
		 WHEN portevt.IsGrossAmountDividend = 1 THEN IIF(portevt.ReinvestFlag = 1, inv.Description, portevtinv.Description)
		 WHEN portevt.IsInterest = 1 THEN portevtinv.Description
		 WHEN portevt.IsGrossAmountInterest = 1 THEN portevtinv.Description
		 ELSE inv.Description END AS Invest,

	CASE WHEN portevt.IsDividend = 1 THEN IIF( portevt.ReinvestFlag = 1 AND jel.AccountingDate = cast(portevt.ReinvestDate AS DATETIME2(2)), inv.Code, portevtinv.Code)
		 WHEN portevt.IsGrossAmountDividend = 1 THEN IIF( portevt.ReinvestFlag = 1, inv.Code, portevtinv.Code)
		 WHEN portevt.IsInterest = 1 THEN portevtinv.Code
		 WHEN portevt.IsGrossAmountInterest = 1 THEN portevtinv.Code
		 ELSE inv.Code END AS ICode,

	jel.LocalAmount, 
	jel.BookAmount,
	jel.QuantityAmount,
	jel.AccountingDate,
	jel.InvestmentId,
	jel.BasketId,
	jel.StrategyId,
	jel.DenomId,
	jel.FinancialAccountId,
	jel.InventoryStateId,
	jel.LocationAccountId,
	jel.TaxLotId,
	jel.PETaxLotId,
	jel.JEDescriptionId,
	ISNULL( (SELECT cinv.Code FROM aga.Investment cinv WHERE cinv.ChainId = portevt.CounterInvestment), (SELECT pc.Code FROM aga.MediumOfExchange pc WHERE pc.ChainId = inv.PrincipalCurrency))	AS SCurrency,

	CASE WHEN portevt.IsForwardFX = 1 OR portevt.IsSpotFX = 1 THEN portevt.EventDate -- ISNULL(portevt.EventDate, adjustedEvent.EventDate)
		 ELSE jel.AccountingDate	END AS AccountDate,

	ISNULL(portevt.PerShareAmount, 0) AS PershareAmt,

	CASE WHEN portevt.IsDividend = 1 THEN IIF(portevt.ReinvestFlag = 1 AND jel.AccountingDate = cast(portevt.ReinvestDate AS DATETIME2(2)), inv.IsMediumOfExchange, portevtinv.IsMediumOfExchange)
		 WHEN portevt.IsGrossAmountDividend = 1 THEN IIF(portevt.ReinvestFlag = 1, inv.IsMediumOfExchange, portevtinv.IsMediumOfExchange)
		 WHEN portevt.IsInterest = 1 THEN portevtinv.IsMediumOfExchange
		 WHEN portevt.IsGrossAmountInterest = 1 THEN portevtinv.IsMediumOfExchange
		 ELSE inv.IsMediumOfExchange END AS MedofExch,

	CASE WHEN jel.AccountingDate = cast(portevt.ReinvestDate AS DATETIME2(2)) THEN cast(portevt.ReinvestDate AS DATETIME2(2))
		 ELSE NULL END AS RDate,

	portevt.Number AS RealID, 

	IIF(jel.FinancialAccountId IN (aga.fgetFinAcctBId(N'InterestReclaimTaxReceipt'), aga.fgetFinAcctBId(N'DividendReclaimTaxReceipt'),
								   aga.fgetFinAcctBId(N'InterestWithholdingTaxExpense'), aga.fgetFinAcctBId(N'DividendWithholdingTaxExpense')), 1, 0) AS WithholdCheck
FROM bis.JELine jel
LEFT JOIN aga.PortfolioEvent portevt ON cast(jel.PETaxLotId as NVARCHAR(64)) = portevt.Number
LEFT JOIN aga.Investment inv ON inv.Investment_BId = jel.InvestmentId
LEFT JOIN aga.Investment binv ON binv.Investment_BId = jel.BasketId
LEFT JOIN aga.Investment portevtinv ON portevtinv.ChainId = portevt.Investment
left join agaSchema.Class cl on cl.ClassId = portevt.ClassId
WHERE ( (jel.AccountingDate >= @PeriodStart AND jel.AccountingDate <= @PeriodEnd AND jel.KnowledgeDate < @KnowledgeDate) )
	  AND jel.BisId = @BisId


INSERT INTO #tjel2
(
	TDate, Settle, SDate, EventType, EType, GroupByTranID, RealTranID, Invest,
	EventID, EventIDLink, ICode, QuantityAmount, Price, SCurrency, LocalGain, BookGain,
	AccountDate, PershareAmt, DenomId, StrategyId, MedofExch, RDate, RealID, WithholdCheck, InventoryStateId, LocationAccountId, LocalAmount, BookAmount, TaxLotId, PETaxLotId
)
SELECT
	j.TDate, j.Settle, j.SDate, j.EventType, j.EType, j.GroupByTranID, j.RealTranID, j.Invest,
	--IIF( j.RealTranID < 10000, NULL, CONCAT(CAST(j.RealTranID AS nvarchar(128)), N' ') ) AS EventID, -- GEN-6128919 concat {Parent.StaticEventDesc} {Parent.Parent.AdjustmentType}
	IIF(j.RealTranID < 10000, NULL, j.RealTranID) AS EventID,
	IIF(j.RealTranID < 10000, NULL, j.RealTranID) AS EventIDLink,
	j.ICode, j.QuantityAmount,

	CASE WHEN binv.IsFuture = 1 AND (SELECT uinv.IsDebt FROM aga.Investment uinv WHERE binv.UnderlyingInvestment = uinv.ChainId) = 1 THEN portevt.Price --HundredMinusYield
		 WHEN binv.IsForwardFXContract = 1 THEN portevt.tradeFX
		 WHEN portevt.IsForwardFX = 1 OR portevt.IsSpotFX = 1	THEN portevt.ContractFxRate
		 WHEN portevt.IsDividend = 1 AND portevt.ReinvestFlag = 1 AND j.AccountingDate = cast(portevt.ReinvestDate AS DATETIME2(2)) THEN portevt.ReinvestPrice
		 WHEN portevt.IsStockLoanActivity = 1 THEN portevt.Price -- {TaxLotTransaction.PortfolioEvent.Price}
		 WHEN j.Invest = portevtinv.Description AND portevt.IsReorganization = 0 AND portevtinv.IsStif = 0 AND portevt.IsCDXCreditEvent = 1 THEN 100 - portevt.AuctionValue
		 WHEN j.Invest = portevtinv.Description AND portevt.IsReorganization = 0 AND portevtinv.IsStif = 0 AND portevt.Price = 0 AND inv.IsCDSBase = 0 THEN NULL
		 ELSE ISNULL(portevt.Price, NULL) END AS Price, 
	 
	j.SCurrency,
	IIF(fa.AccountBaseType = 3 OR fa.AccountBaseType = 4, (-1)*j.LocalAmount, 0) ,  -- 3: Reveue 4: Expense
	IIF(fa.AccountBaseType = 3 OR fa.AccountBaseType = 4, (-1)*j.BookAmount, 0),
	j.AccountDate,
	j.PershareAmt,
	j.DenomId,
	j.StrategyId,
	j.MedofExch,
	j.RDate, 
	j.RealID, 
	j.WithholdCheck,
	j.InventoryStateId, 
	j.LocationAccountId,
	j.LocalAmount,
	j.BookAmount, 
	j.TaxLotId, 
	j.PETaxLotId
FROM #tjel j
LEFT JOIN aga.PortfolioEvent portevt ON cast(j.PETaxLotId as NVARCHAR(64)) = portevt.Number
LEFT JOIN aga.Investment portevtinv ON portevtinv.ChainId = portevt.Investment
LEFT JOIN aga.Investment inv ON inv.Investment_BId = j.InvestmentId
LEFT JOIN aga.FinancialAccount fa ON fa.FinancialAccount_BId = j.FinancialAccountId
LEFT JOIN aga.Investment binv ON binv.Investment_BId = j.BasketId
WHERE ((portevt.EventDate >= @PeriodStart AND portevt.EventDate <= @PeriodEnd) OR j.DescriptionId != 0 OR (portevt.IsCDXCreditEvent = 1 AND portevt.AuctionDate >= @PeriodStart AND portevt.AuctionDate <= @PeriodEnd ))
	  AND ( 1 = IIF(portevt.IsPrePaid = 1 AND portevt.CreatedByExpenseModule = 1 AND aga.[fgetFinAcctCode](j.FinancialAccountId) IN (N'OnHand', 'OnHandIncome'), 0, 1) )
	  AND ( j.TDate = j.AccountDate OR [aga].[fIsChildOfFinacct](@AllRevExpID, j.FinancialAccountId) = 1 OR j.Settle = j.AccountDate OR ( j.EType IN (N'Dividend', N'Repo', N'ReverseRepo', N'CommissionSettlement', N'Closed Period Adjustments', N'DrawDown', N'Rollover', N'CreditActivity',
					N'ReclaimReceipt', N'BulkSettlement', N'InDefault', N'CDXCreditEvent') OR j.DescriptionId != 0 ) ) -- OR {Parent.StaticEventDesc}
	  --AND ( @EventType = N'' OR {PortfolioEvent.EventType} == @EventType ) GEN-6128879
	  AND (@SettleCurrency = N'' OR j.SCurrency = @SettleCurrency OR (j.SCurrency = N'' AND (SELECT Code FROM aga.MediumOfExchange m WHERE m.MediumOfExchange_BId = j.DenomId) = @SettleCurrency) )
	  AND aga.fgetFinAcctCode(j.FinancialAccountId) NOT IN (N'OriginalFace', N'CommissionExpense', N'MarkToMarketPrice', N'STIFInterestStat', N'TaxLotDate', N'SLCAccrualInfo', N'SLCCouponInfo')
	  AND (portevt.IsBorrowSecurity = 1 OR aga.fgetFinAcctCode(j.FinancialAccountId) != N'LastAccrualDate')
	  AND aga.fgetInvStateCode(j.InventoryStateId) NOT IN (N'ContributedCost', N'CustodianXfer', N'PurchasedAI', N'SoldAI', N'GenevaDateRef')
	  AND fa.AccountBaseType != 2 --OwnersEquity
	  AND NOT ( (portevt.IsBorrowSecurity = 1 OR portevt.IsStockLoanActivity = 1 OR portevt.IsLendSecurity = 1) AND binv.IsBorrowLendContract = 1)
	  AND (portevt.IsCreditActivity = 1 OR  (portevt.IsBorrowSecurity = 1 OR portevt.IsStockLoanActivity = 1 OR portevt.IsLendSecurity = 1) OR fa.FinancialAccountRole != 1) --financial account role 1 stands for Notational
	  AND j.PETaxLotId NOT BETWEEN 499 AND 3401 -- GEN-6129015


INSERT INTO #troutine
(
	EventID, TDate, SDate, EventType, Invest, LocationAccountId, DenomId, Quantity, LocalGain, BookGain, LocalNet, BookNet, Price, PETaxLotId, RDate, PershareAmt, Scurrency, EType 
)
SELECT 

	--CASE WHEN @Group1 = N'None' THEN N''
	--	 ELSE N'Grouping()' END AS Group1, --GEN-6128341
	--CASE WHEN @Group2 = N'None' THEN N''
	--	 ELSE N'Grouping()' END AS Group2, --GEN-6128341
	j.EventID,	--	AS [Tran ID],
	j.TDate,
	j.SDate, j.EventType, 
	j.Invest,
	j.LocationAccountId,
	j.DenomId,

	SUM(CASE WHEN j.InventoryStateId != aga.fgetInvStateBId(N'CFInReserve') AND j.InventoryStateId != aga.fgetInvStateBId(N'Informational') 
			    THEN IIF(j.EType = N'Define Global Amount', j.LocalAmount + j.LocalGain, j.QuantityAmount)
		 ELSE 0 END) AS Quantity,
	
	SUM(j.LocalGain),
	SUM(J.BookGain),

	SUM(CASE WHEN j.InventoryStateId != aga.fgetInvStateBId(N'CFInReserve') AND j.InventoryStateId != aga.fgetInvStateBId(N'Informational') 
				THEN IIF(portevt.IsCreditActivity = 1, 0, j.LocalGain + j.LocalAmount)
		 ELSE 0 END) AS LocalNet,

	SUM(CASE WHEN j.InventoryStateId != aga.fgetInvStateBId(N'CFInReserve') AND j.InventoryStateId != aga.fgetInvStateBId(N'Informational') 
				THEN IIF(portevt.IsCreditActivity = 1, 0, j.BookGain + j.BookAmount)
		 ELSE 0 END) AS BookNet,
	
	j.Price,
	j.PETaxLotId,
	j.RDate,
	j.PershareAmt,
	j.SCurrency, 
	j.EType

FROM #tjel2 j
LEFT JOIN aga.PortfolioEvent portevt ON cast(j.PETaxLotId as NVARCHAR(64)) = portevt.Number
LEFT JOIN aga.LocationAccount Custodian ON Custodian.LocationAccount_BId = j.LocationAccountId
LEFT JOIN aga.MediumOfExchange denom ON denom.Investment_BId = j.DenomId

GROUP BY  
		 --CASE WHEN @Group1 = N'None' THEN N''
			--  ELSE N'Grouping()' END, --Group1
		 --CASE WHEN @Group2 = N'None' THEN N''
			--  ELSE N'Grouping()' END, --Group2 
		 j.GroupByTranID, j.EventID, j.EventType, IIF(portevt.IsTransfer = 1, j.StrategyId, NULL), j.LocationAccountId, j.ICode, j.WithholdCheck, j.EType, j.RDate, j.TDate, j.SDate, j.Invest, j.DenomId, j.Price, j.PETaxLotId, j.PershareAmt, j.SCurrency


INSERT #tprint
(
	EventID, TDate, SDate, EventType, Invest, Quantity, LocalGain, BookGain, LocalNet, BookNet, Price, PETaxLotId, RDate, SCurrency, Custodian 
)
SELECT 
	EventID, TDate, SDate, EventType, Invest,
	CASE WHEN  (portevt.IsDividend = 1 OR portevt.IsGrossAmountDividend = 1 OR portevt.IsGrossAmountInterest = 1 OR portevt.IsInterest = 1)
			   THEN IIF(r.PerShareAmt != 0 AND (portevt.ReinvestFlag = 0 OR r.TDate != r.RDate), IIF(r.SCurrency != @BookCurrency, NULL, ROUND(r.LocalGain/r.PerShareAmt, 0)), IIF(portevt.ReinvestFlag = 0, NULL, r.Quantity))
		 WHEN r.EType = N'Reclaim' OR r.EType = N'Withholding' THEN NULL -- in rsl, set it to "" not N/A
		 WHEN portevt.IsDefaultBond = 1 THEN NULL --in rsl set it to N/A
		 ELSE r.Quantity END AS Quantity,

	LocalGain, BookGain, LocalNet, BookNet,

	CASE WHEN  (portevt.IsDividend = 1 OR portevt.IsGrossAmountDividend = 1 OR portevt.IsGrossAmountInterest = 1 OR portevt.IsInterest = 1)
			   THEN IIF(r.PerShareAmt != 0 AND (portevt.ReinvestFlag = 0 OR r.TDate != r.RDate), IIF(r.SCurrency != @BookCurrency, r.Price, IIF(portevtinv.IsStif = 0, r.PerShareAmt, r.Price)), IIF(portevt.ReinvestFlag = 0, NULL, r.Price))
		  WHEN portevt.IsDefaultBond = 1 THEN NULL --in rsl set it to N/A 
		  ELSE r.Price END AS Price,
	PETaxLotId, RDate,
	IIF(r.SCurrency = NULL OR r.SCurrency = N'', denom.Code, r.SCurrency) AS SCurrency,
	loc.NameSort custodianaccount
FROM
#troutine r
LEFT JOIN aga.PortfolioEvent portevt ON cast(r.PETaxLotId as NVARCHAR(64)) = portevt.Number
LEFT JOIN aga.MediumOfExchange denom ON denom.Investment_BId = r.DenomId
LEFT JOIN aga.Investment portevtinv ON portevtinv.ChainId = portevt.Investment
LEFT JOIN aga.LocationAccount loc ON loc.LocationAccount_BId = r.LocationAccountId

SELECT 
	p.TDate, 
	p.SDate, 
	p.EventType as [TranType],
	p.EventID, 
	p.Invest, 
	p.Custodian, 
	p.Quantity, 
	p.Price, 
	p.SCurrency AS Curr, 
	p.LocalNet, 
	p.BookNet, 
	p.LocalGain, 
	p.BookGain
FROM #tprint p
LEFT JOIN aga.PortfolioEvent portevt ON cast(p.PETaxLotId as NVARCHAR(64)) = portevt.Number
WHERE  portevt.IsRepo = 1 OR portevt.IsReverseRepo = 1 OR portevt.IsPrePaid = 1 OR portevt.IsCreditActivity = 1
		OR (portevt.IsForwardFX = 1 AND p.BookGain != 0 AND (p.BookGain > 0.001 OR p.BookGain < - 0.001))
		OR (p.Quantity != 0 AND (p.Quantity > 0.001 OR p.Quantity < -0.001))
		OR (p.LocalNet != 0 AND (p.LocalNet > 0.001 OR p.LocalNet < -0.001))
		OR (p.LocalGain != 0 AND (p.LocalGain > 0.001 OR p.LocalGain < -0.001))
end