export function normalizePhone(value: string) {
  let digits = value.replace(/\D/g, "");

  if (digits.startsWith("55") && digits.length >= 12) {
    digits = digits.slice(2);
  }

  while (digits.length > 11 && digits.startsWith("0")) {
    digits = digits.slice(1);
  }

  if (digits.length > 11) {
    digits = digits.slice(-11);
  }

  return digits;
}

export function formatPhone(value: string) {
  const digits = normalizePhone(value);
  if (digits.length <= 2) return digits;

  const ddd = digits.slice(0, 2);
  const number = digits.slice(2);

  if (number.length <= 4) {
    return `(${ddd}) ${number}`;
  }

  if (number.length <= 8) {
    return `(${ddd}) ${number.slice(0, 4)}-${number.slice(4)}`;
  }

  return `(${ddd}) ${number.slice(0, 5)}-${number.slice(5)}`;
}
