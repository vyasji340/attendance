-- Pehle purani cheezein saaf (dobara run karna safe hai, par is se employees/attendance ka data mit jata hai)
drop table if exists attendance, salaries, adjustments, holidays, settings, employee_pins, employees cascade;
drop function if exists public_employees();
drop function if exists admin_set_pin(uuid, text);
drop function if exists punch(uuid, text, text);

-- Supabase > SQL Editor me poora paste karke Run karo
create extension if not exists pgcrypto with schema extensions;

create table if not exists admins (user_id uuid primary key references auth.users(id) on delete cascade);
create or replace function is_admin() returns boolean language sql security definer stable set search_path = public as
$$ select exists (select 1 from admins where user_id = auth.uid()) $$;

create table employees (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  monthly_salary numeric not null default 0,
  joined_on date not null default (now() at time zone 'Asia/Kolkata')::date,
  active boolean not null default true,
  created_at timestamptz default now()
);
create table employee_pins (
  employee_id uuid primary key references employees(id) on delete cascade,
  pin_hash text not null, fails int not null default 0, locked_until timestamptz
);
create table attendance (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  day date not null,
  in_time timestamptz, lunch_out timestamptz, lunch_in timestamptz, out_time timestamptz,
  status text check (status in ('present','half_day','leave','absent','holiday')),
  note text,
  unique (employee_id, day)
);
create table holidays (day date primary key, name text not null);
create table settings (
  id int primary key default 1 check (id = 1),
  shift_start time not null default '10:00',
  grace_min int not null default 15,
  full_hours numeric not null default 8,
  half_hours numeric not null default 4,
  weekly_off int[] not null default '{0}',
  ot_mult numeric not null default 0
);
insert into settings default values;
create table adjustments (
  employee_id uuid references employees(id) on delete cascade,
  month text, bonus numeric not null default 0, deduction numeric not null default 0,
  primary key (employee_id, month)
);

-- Sab kuch sirf admin ke liye (PIN table par koi policy nahi = koi nahi padh sakta)
alter table employees enable row level security;
alter table employee_pins enable row level security;
alter table attendance enable row level security;
alter table holidays enable row level security;
alter table settings enable row level security;
alter table adjustments enable row level security;
create policy "admin" on employees   for all using (is_admin()) with check (is_admin());
create policy "admin" on attendance  for all using (is_admin()) with check (is_admin());
create policy "admin" on holidays    for all using (is_admin()) with check (is_admin());
create policy "admin" on settings    for all using (is_admin()) with check (is_admin());
create policy "admin" on adjustments for all using (is_admin()) with check (is_admin());

-- Employee screen ke liye sirf naam ki list
create function public_employees() returns table(id uuid, name text)
language sql security definer set search_path = public as
$$ select id, name from employees where active order by name $$;

create function admin_set_pin(p_emp uuid, p_pin text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_admin() then raise exception 'Allowed nahi'; end if;
  if p_pin !~ '^[0-9]{4,6}$' then raise exception 'PIN 4 se 6 number ka hona chahiye'; end if;
  insert into employee_pins(employee_id, pin_hash) values (p_emp, crypt(p_pin, gen_salt('bf')))
  on conflict (employee_id) do update set pin_hash = excluded.pin_hash, fails = 0, locked_until = null;
end $$;

-- Employee khud attendance lagata hai: PIN check + server ka time (fake time nahi chalega)
create function punch(p_emp uuid, p_pin text, p_action text) returns json
language plpgsql security definer set search_path = public, extensions as $$
declare e employees%rowtype; pr employee_pins%rowtype; r attendance%rowtype;
        d date := (now() at time zone 'Asia/Kolkata')::date;
begin
  select * into e from employees where id = p_emp and active;
  select * into pr from employee_pins where employee_id = p_emp;
  if e.id is null or pr.employee_id is null then return json_build_object('error','Employee ya PIN set nahi hai'); end if;
  if pr.locked_until is not null and pr.locked_until > now() then
    return json_build_object('error','Bahut galat PIN. 10 minute baad try karo'); end if;
  if pr.pin_hash <> crypt(p_pin, pr.pin_hash) then
    update employee_pins set fails = case when fails + 1 >= 5 then 0 else fails + 1 end,
      locked_until = case when fails + 1 >= 5 then now() + interval '10 minutes' else null end
    where employee_id = p_emp;
    return json_build_object('error','PIN galat hai');
  end if;
  update employee_pins set fails = 0 where employee_id = p_emp and fails > 0;
  select * into r from attendance where employee_id = p_emp and day = d;
  if p_action <> 'status' and r.status in ('leave','absent','holiday') then
    return json_build_object('error','Aaj ka status admin ne set kar diya hai'); end if;
  if p_action = 'in' then
    if r.in_time is not null then return json_build_object('error','IN pehle hi ho chuka hai'); end if;
    insert into attendance(employee_id, day, in_time) values (p_emp, d, now())
      on conflict (employee_id, day) do update set in_time = now();
  elsif p_action = 'lunch_out' then
    if r.in_time is null or r.lunch_out is not null or r.out_time is not null then
      return json_build_object('error','Abhi Lunch OUT nahi ho sakta'); end if;
    update attendance set lunch_out = now() where id = r.id;
  elsif p_action = 'lunch_in' then
    if r.lunch_out is null or r.lunch_in is not null or r.out_time is not null then
      return json_build_object('error','Abhi Lunch IN nahi ho sakta'); end if;
    update attendance set lunch_in = now() where id = r.id;
  elsif p_action = 'out' then
    if r.in_time is null or r.out_time is not null then return json_build_object('error','Abhi OUT nahi ho sakta'); end if;
    if r.lunch_out is not null and r.lunch_in is null then return json_build_object('error','Pehle Lunch IN karo'); end if;
    update attendance set out_time = now() where id = r.id;
  elsif p_action <> 'status' then
    return json_build_object('error','Galat action');
  end if;
  select * into r from attendance where employee_id = p_emp and day = d;
  return json_build_object('name', e.name, 'att', to_json(r));
end $$;
