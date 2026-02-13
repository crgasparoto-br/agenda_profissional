-- Normalize legacy pending appointments to scheduled.
update appointments
set status = 'scheduled'
where status = 'pending';
