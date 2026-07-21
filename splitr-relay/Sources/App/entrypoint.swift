import Vapor

@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)
        // Bind all interfaces by default so a phone on the same LAN can reach
        // the Mac during two-device testing (override with RELAY_HOST/PORT).
        app.http.server.configuration.hostname = Environment.get("RELAY_HOST") ?? "0.0.0.0"
        app.http.server.configuration.port = Environment.get("RELAY_PORT").flatMap(Int.init) ?? 8080

        do {
            try await configure(app)
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.execute()
        try await app.asyncShutdown()
    }
}
