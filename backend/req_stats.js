const _stats = { total: 0, byRoute: {}, startMs: Date.now() };

function middleware(req, res, next) {
    _stats.total++;
    const key = `${req.method} ${req.baseUrl || ''}${req.path}`;
    _stats.byRoute[key] = (_stats.byRoute[key] || 0) + 1;
    next();
}

function getStats() {
    return {
        total: _stats.total,
        uptimeSeconds: Math.round((Date.now() - _stats.startMs) / 1000),
        topRoutes: Object.entries(_stats.byRoute)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 25)
            .map(([route, count]) => ({ route, count })),
    };
}

module.exports = { middleware, getStats };
