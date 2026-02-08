import { z } from "npm:zod@3.23.8";

export const BootstrapTenantInputSchema = z.object({
  tenant_type: z.enum(["individual", "group"]),
  tenant_name: z.string().trim().min(2).max(120),
  full_name: z.string().trim().min(2).max(120),
  phone: z.string().trim().min(8).max(30).optional().default("")
});

export const CreateAppointmentInputSchema = z
  .object({
    client_id: z.string().uuid().nullable(),
    service_id: z.string().uuid(),
    starts_at: z.string().datetime(),
    ends_at: z.string().datetime(),
    professional_id: z.string().uuid().nullable(),
    any_available: z.boolean().default(false)
  })
  .superRefine((value, ctx) => {
    const starts = new Date(value.starts_at);
    const ends = new Date(value.ends_at);

    if (Number.isNaN(starts.getTime()) || Number.isNaN(ends.getTime())) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Invalid dates" });
      return;
    }

    if (ends <= starts) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "ends_at must be after starts_at" });
    }

    if (value.any_available && value.professional_id) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "professional_id must be null when any_available=true"
      });
    }

    if (!value.any_available && !value.professional_id) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "professional_id is required when any_available=false"
      });
    }
  });

export const AppointmentResponseSchema = z.object({
  id: z.string().uuid(),
  tenant_id: z.string().uuid(),
  professional_id: z.string().uuid(),
  service_id: z.string().uuid(),
  status: z.enum(["pending", "scheduled", "confirmed", "cancelled", "rescheduled", "no_show", "done"]),
  starts_at: z.string().datetime(),
  ends_at: z.string().datetime(),
  assigned_at: z.string().datetime().nullable(),
  assigned_by: z.string().uuid().nullable()
});
