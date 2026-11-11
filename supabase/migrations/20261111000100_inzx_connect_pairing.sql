begin;

create schema if not exists inzx_connect;
revoke all on schema inzx_connect from public, anon, authenticated;

create table inzx_connect.devices (
  id uuid primary key references auth.users(id) on delete cascade,
  label text not null check (char_length(label) between 1 and 48)
);

create table inzx_connect.invitations (
  host uuid primary key references inzx_connect.devices(id) on delete cascade,
  code_hash bytea unique not null,
  expires_at timestamptz not null,
  requester uuid references inzx_connect.devices(id) on delete cascade,
  check (requester is distinct from host)
);

create table inzx_connect.pairs (
  first_device uuid references inzx_connect.devices(id) on delete cascade,
  second_device uuid references inzx_connect.devices(id) on delete cascade,
  primary key (first_device, second_device),
  check (first_device < second_device)
);

alter table inzx_connect.devices enable row level security;
alter table inzx_connect.invitations enable row level security;
alter table inzx_connect.pairs enable row level security;
create index on inzx_connect.invitations (requester);
create index on inzx_connect.pairs (second_device);

create function public.inzx_connect_register(device_label text)
returns void language sql security definer set search_path = '' as $$
  insert into inzx_connect.devices (id, label)
  values (auth.uid(), left(trim(device_label), 48))
  on conflict (id) do update set label = excluded.label;
$$;

create function public.inzx_connect_create_invite()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  device uuid := auth.uid();
  code text := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
  expiry timestamptz := now() + interval '2 minutes';
begin
  insert into inzx_connect.invitations (host, code_hash, expires_at)
  values (device, sha256(convert_to(code, 'UTF8')), expiry)
  on conflict (host) do update
    set code_hash = excluded.code_hash, expires_at = excluded.expires_at,
        requester = null;
  return jsonb_build_object('code', code, 'expires_at', expiry);
end;
$$;

create function public.inzx_connect_scan_invite(pairing_code text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  device uuid := auth.uid();
begin
  if pairing_code is null or pairing_code !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid pairing code';
  end if;
  update inzx_connect.invitations
  set requester = device
  where code_hash = sha256(convert_to(pairing_code, 'UTF8'))
    and expires_at > now()
    and host <> device
    and (requester is null or requester = device);
  if not found then
    raise exception 'This pairing code is unavailable';
  end if;
end;
$$;

create function public.inzx_connect_status()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'label', d.label)
        order by d.label, d.id)
      from inzx_connect.pairs p
      join inzx_connect.devices d
        on d.id = case when p.first_device = auth.uid()
          then p.second_device else p.first_device end
      where auth.uid() in (p.first_device, p.second_device)
    ), '[]'::jsonb),
    'incoming', (
      select jsonb_build_object('id', d.id, 'label', d.label)
      from inzx_connect.invitations i
      join inzx_connect.devices d on d.id = i.requester
      where i.host = auth.uid() and i.expires_at > now()
    ),
    'waiting_for', (
      select d.label
      from inzx_connect.invitations i
      join inzx_connect.devices d on d.id = i.host
      where i.requester = auth.uid() and i.expires_at > now()
      order by i.expires_at desc limit 1
    )
  );
$$;

create function public.inzx_connect_decide(peer uuid, pairing_code text, approve boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  device uuid := auth.uid();
begin
  -- Deleting the matching invitation consumes it in the same transaction as
  -- granting access. Stale confirmations cannot approve a replacement QR.
  delete from inzx_connect.invitations
  where host = device and requester = peer and expires_at > now()
    and code_hash = sha256(convert_to(pairing_code, 'UTF8'));
  if not found then
    raise exception 'This pairing request has expired';
  end if;
  if approve then
    insert into inzx_connect.pairs values (least(device, peer), greatest(device, peer))
    on conflict do nothing;
  end if;
end;
$$;

create function public.inzx_connect_unpair(peer uuid)
returns void language sql security definer set search_path = '' as $$
  delete from inzx_connect.invitations
    where (host = auth.uid() and requester = peer)
      or (host = peer and requester = auth.uid());
  delete from inzx_connect.pairs
    where first_device = least(auth.uid(), peer)
      and second_device = greatest(auth.uid(), peer);
$$;

revoke execute on function public.inzx_connect_register(text),
  public.inzx_connect_create_invite(), public.inzx_connect_scan_invite(text),
  public.inzx_connect_status(), public.inzx_connect_decide(uuid, text, boolean),
  public.inzx_connect_unpair(uuid) from public, anon;
grant execute on function public.inzx_connect_register(text),
  public.inzx_connect_create_invite(), public.inzx_connect_scan_invite(text),
  public.inzx_connect_status(), public.inzx_connect_decide(uuid, text, boolean),
  public.inzx_connect_unpair(uuid) to authenticated;

commit;
