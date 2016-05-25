if exists (select * from sys.objects where object_id = OBJECT_ID(N'[dbo].[ReportTWRPerfSum]') and type in (N'P', N'PC'))
drop procedure [dbo].[ReportTWRPerfSum]
go

create procedure [dbo].[ReportTWRPerfSum]
	@Portfolios nvarchar(255)--,
	--@AccountingRunType nvarchar(255),
	--@AccountingCalendar nvarchar(255),
	--@AccountingPeriod nvarchar(255),
	--@PeriodEndDate datetime,
	--@KnowledgeDate datetime

-- exec [dbo].[ReportTWRPerfSum] @Portfolios = 'Cardinal Capital'

as begin
	--if @PeriodEndDate is null select @PeriodEndDate = getdate();
	--if @KnowledgeDate is null select @KnowledgeDate = getdate();
	declare
		@SessionID uniqueidentifier,
		@AppServer nvarchar(1000) = 'GVAOD-APP01.advent.com',
		@Host nvarchar(255) = 'optcs3.advent.com',
		@Port int = 11001,
		@UserName nvarchar(255) = 'accessadmin',
		@Password nvarchar(255) = 'welcome';

	exec GenevaLogin 
		@AppServer = @AppServer,
		@Host = @Host,
		@Port = @Port,
		@UserName = @UserName,
		@Password = @Password,
		@SessionID = @SessionID out;

	declare @temp table (Invest nvarchar(255), InvestDesc nvarchar(255), Qty float, Price float, PriceDate datetime, PriceStatus nvarchar(255), PriceRange float, PriceList nvarchar(255), PriceLevel  nvarchar(255), Currency nvarchar(255), PriceDenom nvarchar(255))

	if @SessionID is not null
	begin
		declare @command nvarchar(max),
			@RSL nvarchar(255) = 'twrperfsum',
			@format nvarchar(32) = 'Data'

		set @command = '-p "Cardinal Capital" -ps 2015/06/01 -pe 2015/07/14:19:24:08 -k 2015/07/14:19:24:12 -pk 2015/06/30:23:59:59 --AccountingPeriod June-2015 --AccountingCalendar def -at TWR --ReportPeriodEndDate 2015/07/14:19:24:08 --TWRLevel2 Portfolio --PerformanceParameters CardinalCapitalPerfParam --OpeningFlowMethod "Long Short Tax Lots" --TWRInceptionDate "January 1, 2012 12:00:00 am" --DoNotApplyTWRAdjustments 0 --PerformanceFee GrossOfFees --UseHistPeriodData 1 --PerformanceWithholding NetIncludingReclaim --PerformanceMethod IRR_ModifiedDietz --SummarizeChangeInPort 0' --+= char(34) + @Portfolios + char(34) + ' -pe ' + replace(convert(varchar(23), @PeriodEndDate, 120),' ','') + ' -k ' + replace(convert(varchar(23), @KnowledgeDate, 120),' ','') + ' -at ' + @AccountingRunType + ' --AccountingCalendar ' + @AccountingCalendar + ' --AccountingPeriod ' + @AccountingPeriod
		exec GenevaRSL @SessionID, @RSL, @format, @command

	--	Kill the session, free up that seat!
		exec GenevaLogout @SessionID
	end
	else
	begin
		print 'No valid session.'
	end

end
GO


