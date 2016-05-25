if exists (select * from sys.objects where object_id = OBJECT_ID(N'[dbo].[ReportTaxLotAppraisal]') and type in (N'P', N'PC'))
drop procedure [dbo].[ReportTaxLotAppraisal]
go

create procedure [dbo].[ReportTaxLotAppraisal]
	@Portfolios nvarchar(255),
	@PeriodEndDate datetime,
	@KnowledgeDate datetime
/*
exec [dbo].[ReportTaxLotAppraisal]
	@Portfolios = 'Cardinal Capital',
	@PeriodEndDate = NULL,
	@KnowledgeDate = NULL
*/
as begin
	if @PeriodEndDate is null select @PeriodEndDate = getdate();
	if @KnowledgeDate is null select @KnowledgeDate = getdate();
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
		declare @command nvarchar(max) = '-p ',
			@RSL nvarchar(255) = 'taxlotappacc',
			@format nvarchar(32) = 'Data'

		set @command += char(34) + @Portfolios + char(34) + ' -pe ' + replace(convert(varchar(23), @PeriodEndDate, 120),' ','') + ' -k ' + replace(convert(varchar(23), @KnowledgeDate, 120),' ','')
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


