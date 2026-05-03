import IORedis, { type Redis, type RedisOptions } from 'ioredis';
import { env } from './env.js';

const baseOptions: RedisOptions = {
  maxRetriesPerRequest: null,
  enableReadyCheck: true,
  lazyConnect: false,
};

let _connection: Redis | undefined;

export function getRedis(): Redis {
  if (!_connection) {
    _connection = new IORedis(env.REDIS_URL, baseOptions);
  }
  return _connection;
}

/** Each BullMQ Worker / Queue / QueueEvents needs its own connection. */
export function createRedisConnection(): Redis {
  return new IORedis(env.REDIS_URL, baseOptions);
}
