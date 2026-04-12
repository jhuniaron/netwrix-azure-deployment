using Microsoft.AspNetCore.Mvc.Testing;
using System.Net;
using System.Text.Json;

namespace Netwrix.DevOps.Test.App.Tests;

[TestClass]
public class HealthEndpointTests
{
    private static WebApplicationFactory<Program> _factory = null!;
    private static HttpClient _client = null!;

    [ClassInitialize]
    public static void Init(TestContext _)
    {
        // Spins up the real app in-memory — no network, no Azure needed
        _factory = new WebApplicationFactory<Program>();
        _client = _factory.CreateClient();
    }

    [ClassCleanup]
    public static void Cleanup()
    {
        _client.Dispose();
        _factory.Dispose();
    }

    [TestMethod]
    public async Task HealthEndpoint_Returns200()
    {
        var response = await _client.GetAsync("/health");
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
    }

    [TestMethod]
    public async Task HealthEndpoint_ReturnsHealthyStatus()
    {
        var response = await _client.GetAsync("/health");
        var body = await response.Content.ReadAsStringAsync();
        var json = JsonDocument.Parse(body).RootElement;

        // The "status" field must equal "healthy"
        Assert.AreEqual("healthy", json.GetProperty("status").GetString());
    }

    [TestMethod]
    public async Task HealthEndpoint_ReturnsTimestamp()
    {
        var response = await _client.GetAsync("/health");
        var body = await response.Content.ReadAsStringAsync();
        var json = JsonDocument.Parse(body).RootElement;

        // A timestamp field must be present
        Assert.IsTrue(json.TryGetProperty("timestamp", out _),
            "Response should contain a 'timestamp' field");
    }

    [TestMethod]
    public async Task RootEndpoint_Returns200()
    {
        var response = await _client.GetAsync("/");
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);
    }

    [TestMethod]
    public async Task RootEndpoint_MentionsDotNet10()
    {
        var response = await _client.GetAsync("/");
        var body = await response.Content.ReadAsStringAsync();

        // Confirms the right app version is running
        StringAssert.Contains(body, ".NET 10");
    }
}
