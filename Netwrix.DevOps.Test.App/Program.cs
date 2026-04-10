var builder = WebApplication.CreateBuilder(args);

// Add Application Insights telemetry if connection string is configured
builder.Services.AddApplicationInsightsTelemetry();

var app = builder.Build();

// Health check endpoint — required by Application Gateway health probe
app.MapGet("/health", () => Results.Ok(new { status = "healthy", timestamp = DateTime.UtcNow }));

app.MapGet("/", () => "Netwrix DevOps Test App — Running on .NET 10 / Linux");

app.Run();
