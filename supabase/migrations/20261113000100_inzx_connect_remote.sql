-- Inzx Connect remote control: lets paired devices see each other's playback
-- and control it over Supabase Realtime.
--
-- Every device listens on its own private broadcast topic,
-- `inzx-connect:<device id>`. It publishes its playback state there and
-- takes commands from there. A device may read from and send to its own topic
-- and the topics of devices it is paired with, and nothing else.
--
-- Run once, after 20261111000100_inzx_connect_pairing.sql.

begin;

create function public.inzx_connect_can_use_topic(topic text)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and (
    topic = 'inzx-connect:' || auth.uid()::text
    or exists (
      select 1
      from inzx_connect.pairs p
      where auth.uid() in (p.first_device, p.second_device)
        and topic = 'inzx-connect:' || (
          case when p.first_device = auth.uid()
            then p.second_device else p.first_device end
        )::text
    )
  );
$$;

revoke execute on function public.inzx_connect_can_use_topic(text)
  from public, anon;
grant execute on function public.inzx_connect_can_use_topic(text)
  to authenticated;

create policy "Inzx Connect devices receive from paired topics"
  on realtime.messages for select to authenticated
  using (
    realtime.messages.extension = 'broadcast'
    and realtime.topic() like 'inzx-connect:%'
    and public.inzx_connect_can_use_topic(realtime.topic())
  );

create policy "Inzx Connect devices send to paired topics"
  on realtime.messages for insert to authenticated
  with check (
    realtime.messages.extension = 'broadcast'
    and realtime.topic() like 'inzx-connect:%'
    and public.inzx_connect_can_use_topic(realtime.topic())
  );

commit;
