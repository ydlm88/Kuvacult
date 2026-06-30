const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');

const pool = new Pool({
    host: process.env.PG_HOST || 'localhost',
    port: parseInt(process.env.PG_PORT) || 5432,
    database: process.env.PG_DB || 'kuvacult',
    user: process.env.PG_USER || 'postgres',
    password: process.env.PG_PASSWORD,
});

async function migrate() {
    const sql = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
    await pool.query(sql);
    console.log('DB schema verified.');
}

const query = (text, params) => pool.query(text, params);

module.exports = { pool, query, migrate };
