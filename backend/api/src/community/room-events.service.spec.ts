import { EventEmitter, getEventListeners } from 'node:events';
import type { Client } from 'pg';
import type { DatabaseService } from '../database/database.service.js';
import { RoomEventsService } from './room-events.service.js';

function setup() {
  const clients: (EventEmitter & {
    query: ReturnType<typeof vi.fn>;
    end: ReturnType<typeof vi.fn>;
  })[] = [];
  const roomListener = vi.fn(async () => {
    const client = Object.assign(new EventEmitter(), {
      query: vi.fn(async () => ({})),
      end: vi.fn(async () => {}),
    });
    clients.push(client);
    return client as unknown as Client;
  });
  return {
    service: new RoomEventsService({
      roomListener,
    } as unknown as DatabaseService),
    clients,
    roomListener,
  };
}

describe('Room event subscriptions', () => {
  it('shares a listener, wakes only the changed room, and cleans up cancellations', async () => {
    const { service, clients, roomListener } = setup();
    const a = new AbortController(),
      b = new AbortController();
    const [one, two] = await Promise.all([
      service.watch('one', a.signal),
      service.watch('two', b.signal),
    ]);
    expect(roomListener).toHaveBeenCalledTimes(1);
    let otherWoke = false;
    void two.changed.then(() => {
      otherWoke = true;
    });
    clients[0].emit('notification', {
      channel: 'multiverse_room_changed',
      payload: 'one',
    });
    await one.changed;
    expect(otherWoke).toBe(false);
    expect(getEventListeners(a.signal, 'abort')).toHaveLength(0);
    b.abort();
    await two.changed;
    expect(getEventListeners(b.signal, 'abort')).toHaveLength(0);
    one.dispose();
    two.dispose();
    await service.onModuleDestroy();
  });
  it('wakes disconnected viewers and establishes a fresh listener on retry', async () => {
    const { service, clients, roomListener } = setup();
    const first = await service.watch('room', new AbortController().signal);
    clients[0].emit('error', new Error('connection lost'));
    await first.changed;
    const second = await service.watch('room', new AbortController().signal);
    expect(roomListener).toHaveBeenCalledTimes(2);
    clients[1].emit('notification', {
      channel: 'multiverse_room_changed',
      payload: 'room',
    });
    await second.changed;
    await service.onModuleDestroy();
  });
  it('finishes immediately for an already cancelled request', async () => {
    const { service } = setup();
    const abort = new AbortController();
    abort.abort();
    const watch = await service.watch('room', abort.signal);
    await watch.changed;
    expect(getEventListeners(abort.signal, 'abort')).toHaveLength(0);
    await service.onModuleDestroy();
  });
  it('does not retain new watchers or reconnect after shutdown', async () => {
    const { service, roomListener } = setup();
    await service.onModuleDestroy();
    const abort = new AbortController();
    const watch = await service.watch('room', abort.signal);
    expect(getEventListeners(abort.signal, 'abort')).toHaveLength(0);
    expect(roomListener).not.toHaveBeenCalled();
    await watch.changed;
    watch.dispose();
  });
  it('closes a pending connection before shutdown completes without installing watchers', async () => {
    const { service, clients, roomListener } = setup();
    const createClient = roomListener.getMockImplementation()!;
    let release = () => {};
    const connected = new Promise<void>((resolve) => {
      release = resolve;
    });
    roomListener.mockImplementationOnce(async () => {
      await connected;
      return createClient();
    });
    const abort = new AbortController();
    const pending = service.watch('room', abort.signal);
    const stopping = service.onModuleDestroy();
    release();
    await stopping;
    const watch = await pending;
    expect(clients[0].end).toHaveBeenCalledTimes(1);
    expect(clients[0].query).not.toHaveBeenCalled();
    expect(getEventListeners(abort.signal, 'abort')).toHaveLength(0);
    await watch.changed;
  });
  it('drains existing subscriptions and closes the listener only once', async () => {
    const { service, clients } = setup();
    const abort = new AbortController();
    const watch = await service.watch('room', abort.signal);
    clients[0].end.mockImplementation(async () => {
      clients[0].emit('end');
    });
    await service.onModuleDestroy();
    await watch.changed;
    expect(clients[0].end).toHaveBeenCalledTimes(1);
    expect(getEventListeners(abort.signal, 'abort')).toHaveLength(0);
  });
});
