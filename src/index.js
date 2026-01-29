const express = require('express');
const mysql = require('mysql2/promise');

const app = express();
const PORT = process.env.PORT || 8080;
const ENVIRONMENT = process.env.ENVIRONMENT || 'development';
const LOG_LEVEL = process.env.LOG_LEVEL || 'info';

// Middleware
app.use(express.json());

// Database configuration
const dbConfig = {
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 3306,
  user: process.env.DB_USERNAME,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0
};

let pool = null;

// Initialize database connection pool if configured
if (dbConfig.host && dbConfig.user && dbConfig.database) {
  pool = mysql.createPool(dbConfig);
  console.log('Database connection pool created');
  
  // Test connection immediately on startup
  (async () => {
    try {
      const [rows] = await pool.query('SELECT VERSION() as version, DATABASE() as db, NOW() as time');
      log('info', 'Database connection verified', {
        host: dbConfig.host,
        database: dbConfig.database,
        version: rows[0].version,
        current_db: rows[0].db,
        server_time: rows[0].time
      });
    } catch (error) {
      log('error', 'Failed to verify database connection on startup', {
        host: dbConfig.host,
        database: dbConfig.database,
        error: error.message
      });
    }
  })();
} else {
  log('warn', 'Database not configured - running without database connection', {
    host_provided: !!dbConfig.host,
    user_provided: !!dbConfig.user,
    database_provided: !!dbConfig.database
  });
}

// Logging function
function log(level, message, data = {}) {
  const logLevels = ['debug', 'info', 'warn', 'error'];
  const currentLevel = logLevels.indexOf(LOG_LEVEL);
  const messageLevel = logLevels.indexOf(level);
  
  if (messageLevel >= currentLevel) {
    console.log(JSON.stringify({
      timestamp: new Date().toISOString(),
      level,
      message,
      environment: ENVIRONMENT,
      ...data
    }));
  }
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    environment: ENVIRONMENT,
    uptime: process.uptime()
  });
});

// Readiness check endpoint
app.get('/ready', async (req, res) => {
  const checks = {
    server: true,
    database: false
  };

  // Check database connection if configured
  if (pool) {
    try {
      await pool.query('SELECT 1');
      checks.database = true;
    } catch (error) {
      log('error', 'Database check failed', { error: error.message });
    }
  } else {
    checks.database = true; // No database configured, consider it ready
  }

  const isReady = Object.values(checks).every(check => check === true);
  const statusCode = isReady ? 200 : 503;

  res.status(statusCode).json({
    status: isReady ? 'ready' : 'not ready',
    timestamp: new Date().toISOString(),
    checks
  });
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    message: 'HLF Test Application',
    environment: ENVIRONMENT,
    version: '1.0.0',
    timestamp: new Date().toISOString()
  });
});

// Info endpoint
app.get('/info', (req, res) => {
  res.json({
    application: 'hlf-lab-test-app',
    version: '1.0.0',
    environment: ENVIRONMENT,
    node_version: process.version,
    platform: process.platform,
    memory: {
      total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024) + ' MB',
      used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024) + ' MB'
    },
    uptime: Math.round(process.uptime()) + ' seconds'
  });
});

// Database test endpoint - comprehensive connection test
app.get('/db/test', async (req, res) => {
  if (!pool) {
    return res.status(503).json({
      error: 'Database not configured',
      config: {
        host: dbConfig.host || 'not set',
        port: dbConfig.port,
        database: dbConfig.database || 'not set',
        user: dbConfig.user || 'not set'
      }
    });
  }

  try {
    // Test 1: Basic connectivity
    const [basicTest] = await pool.query('SELECT 1 as test');
    
    // Test 2: Server info
    const [serverInfo] = await pool.query('SELECT NOW() as current_time, VERSION() as version, DATABASE() as current_db, USER() as current_user');
    
    // Test 3: Show tables
    const [tables] = await pool.query('SHOW TABLES');
    
    // Test 4: Connection status
    const [status] = await pool.query('SHOW STATUS WHERE Variable_name = "Threads_connected"');
    
    res.json({
      status: 'connected',
      message: '✅ Database connection successful',
      connection: {
        host: dbConfig.host,
        port: dbConfig.port,
        database: dbConfig.database,
        user: dbConfig.user
      },
      server: {
        version: serverInfo[0].version,
        current_time: serverInfo[0].current_time,
        current_db: serverInfo[0].current_db,
        current_user: serverInfo[0].current_user
      },
      tables_count: tables.length,
      tables: tables.map(t => Object.values(t)[0]),
      connections: status[0] || null
    });
  } catch (error) {
    log('error', 'Database test failed', { 
      error: error.message,
      code: error.code,
      errno: error.errno
    });
    res.status(500).json({
      error: 'Database connection failed',
      message: error.message,
      code: error.code,
      config: {
        host: dbConfig.host,
        port: dbConfig.port,
        database: dbConfig.database,
        user: dbConfig.user
      }
    });
  }
});

// Database write test endpoint
app.post('/db/write-test', async (req, res) => {
  if (!pool) {
    return res.status(503).json({
      error: 'Database not configured'
    });
  }

  try {
    // Create test table if not exists
    await pool.query(`
      CREATE TABLE IF NOT EXISTS test_connection (
        id INT AUTO_INCREMENT PRIMARY KEY,
        test_value VARCHAR(255),
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    
    // Insert test data
    const testValue = `test-${Date.now()}`;
    const [insertResult] = await pool.query(
      'INSERT INTO test_connection (test_value) VALUES (?)',
      [testValue]
    );
    
    // Read back the data
    const [rows] = await pool.query(
      'SELECT * FROM test_connection WHERE id = ?',
      [insertResult.insertId]
    );
    
    res.json({
      status: 'success',
      message: '✅ Database write test successful',
      test: {
        inserted_id: insertResult.insertId,
        test_value: testValue,
        retrieved_data: rows[0]
      }
    });
  } catch (error) {
    log('error', 'Database write test failed', { error: error.message });
    res.status(500).json({
      error: 'Database write test failed',
      message: error.message
    });
  }
});

// Error handling middleware
app.use((err, req, res, next) => {
  log('error', 'Unhandled error', { error: err.message, stack: err.stack });
  res.status(500).json({
    error: 'Internal server error',
    message: err.message
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Not found',
    path: req.path
  });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  log('info', `Server started`, {
    port: PORT,
    environment: ENVIRONMENT,
    database_configured: !!pool
  });
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  log('info', 'SIGTERM received, shutting down gracefully');
  
  if (pool) {
    await pool.end();
    log('info', 'Database connections closed');
  }
  
  process.exit(0);
});

process.on('SIGINT', async () => {
  log('info', 'SIGINT received, shutting down gracefully');
  
  if (pool) {
    await pool.end();
    log('info', 'Database connections closed');
  }
  
  process.exit(0);
});
