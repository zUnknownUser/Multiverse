/** Email-safe tables and inline styles; no remote images, scripts or web fonts. */
export function verificationEmail(code: string, requestedLocale: unknown) {
  if (!/^\d{6}$/.test(code)) throw new Error("Invalid verification code");
  const english = typeof requestedLocale === "string" && /^en(?:[-_]|$)/i.test(requestedLocale);
  const copy = english ? {
    lang: "en", subject: "Your Multiverse verification code",
    preheader: "One last step: confirm your email to join Multiverse.",
    tag: "YOUR NEXT CHAPTER", title: "Every universe starts with you.",
    intro: "Confirm your email to continue creating your Multiverse account.",
    label: "YOUR VERIFICATION CODE", expiry: "Valid for 10 minutes",
    instruction: "Go back to the app and enter these six digits. Keep this code to yourself.",
    safety: "Didn't request this code? You can safely ignore this email.",
    footer: "Your stories. Your universes. Your Multiverse.",
  } : {
    lang: "pt-BR", subject: "Seu código de confirmação Multiverse",
    preheader: "Falta pouco: confirme seu e-mail para entrar no Multiverse.",
    tag: "SEU PRÓXIMO CAPÍTULO", title: "Todo universo começa com você.",
    intro: "Confirme seu e-mail para continuar criando sua conta no Multiverse.",
    label: "SEU CÓDIGO DE CONFIRMAÇÃO", expiry: "Válido por 10 minutos",
    instruction: "Volte ao app e digite estes seis números. Não compartilhe este código.",
    safety: "Não pediu este código? Pode ignorar este e-mail com segurança.",
    footer: "Suas histórias. Seus universos. Seu Multiverse.",
  };
  const text = `${copy.title}\n\n${copy.intro}\n\n${copy.label}: ${code}\n${copy.expiry}\n\n${copy.instruction}\n\n${copy.safety}\n\nMULTIVERSE\n${copy.footer}`;
  const html = `<!doctype html>
<html lang="${copy.lang}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light"><title>${copy.subject}</title></head>
<body style="margin:0;padding:0;background-color:#F5F1E8;color:#16130F;font-family:Arial,Helvetica,sans-serif;-webkit-text-size-adjust:100%;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;mso-hide:all;">${copy.preheader}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" bgcolor="#F5F1E8"><tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;">
<tr><td style="padding:0 0 20px;font-size:26px;font-weight:900;letter-spacing:-1px;color:#16130F;">MULTIVERSE<span style="color:#E4412F;">.</span></td></tr>
<tr><td style="border:2px solid #16130F;background-color:#FFFDF8;box-shadow:6px 6px 0 #16130F;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0">
<tr><td bgcolor="#2E5BE8" style="padding:14px 24px;color:#FFFFFF;font-size:11px;font-weight:bold;letter-spacing:2px;border-bottom:2px solid #16130F;">${copy.tag}</td></tr>
<tr><td style="padding:32px 24px 16px;">
<h1 style="margin:0 0 16px;font-size:32px;line-height:1.12;letter-spacing:-1px;font-weight:900;color:#16130F;">${copy.title}</h1>
<p style="margin:0;font-size:16px;line-height:1.6;color:#6B655B;">${copy.intro}</p>
</td></tr>
<tr><td style="padding:8px 24px 24px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" bgcolor="#F4A814" style="border:2px solid #16130F;">
<tr><td align="center" style="padding:22px 12px 10px;font-size:10px;font-weight:bold;letter-spacing:1px;color:#16130F;">${copy.label}</td></tr>
<tr><td align="center" style="padding:0 8px 12px;font-family:'Courier New',monospace;font-size:36px;line-height:1.3;font-weight:bold;letter-spacing:5px;color:#16130F;">${code}</td></tr>
<tr><td align="center" style="padding:0 12px 22px;font-size:12px;font-weight:bold;color:#16130F;">${copy.expiry}</td></tr>
</table></td></tr>
<tr><td style="padding:0 24px 28px;font-size:14px;line-height:1.6;color:#16130F;">${copy.instruction}</td></tr>
<tr><td style="padding:20px 24px;border-top:2px solid #16130F;background-color:#F5F1E8;font-size:12px;line-height:1.6;color:#6B655B;">${copy.safety}</td></tr>
</table></td></tr>
<tr><td align="center" style="padding:28px 12px 8px;font-size:11px;line-height:1.7;color:#6B655B;">${copy.footer}<br><span style="font-weight:bold;">somosmultiverse.com.br</span></td></tr>
</table></td></tr></table></body></html>`;
  return { subject: copy.subject, text, html };
}
