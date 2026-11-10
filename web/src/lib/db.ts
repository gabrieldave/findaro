import { Pool, type PoolClient, type QueryResultRow } from "pg";

declare global {
  var __findaroPool: Pool | undefined;
}

function databaseUrl(): string {
  const raw = process.env.DATABASE_URL;
  if (!raw) throw new Error("DATABASE_URL no configurada");
  return raw;
}

export function pool(): Pool {
  if (!global.__findaroPool) {
    global.__findaroPool = new Pool({
      connectionString: databaseUrl(),
      max: 5,
      idleTimeoutMillis: 20_000,
    });
  }
  return global.__findaroPool;
}

export async function query<T extends QueryResultRow = QueryResultRow>(
  text: string,
  params?: unknown[],
) {
  return pool().query<T>(text, params);
}

export async function withTransaction<T>(
  fn: (client: PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool().connect();
  try {
    await client.query("BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (err) {
    await client.query("ROLLBACK").catch(() => undefined);
    throw err;
  } finally {
    client.release();
  }
}
