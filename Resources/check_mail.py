#!/usr/bin/python3
import email
import imaplib
import json
import sys
from email.header import decode_header, make_header
from email.utils import parsedate_to_datetime


def decode(value):
    if not value:
        return ""
    try:
        return str(make_header(decode_header(value)))
    except Exception:
        return value


def main():
    if len(sys.argv) != 2:
        raise RuntimeError("缺少邮箱账号")

    account = sys.argv[1]
    password = sys.stdin.read()
    if not password:
        raise RuntimeError("客户端专用密码为空")

    with imaplib.IMAP4_SSL("imap.exmail.qq.com", 993, timeout=20) as mailbox:
        mailbox.login(account, password)
        status, _ = mailbox.select("INBOX", readonly=True)
        if status != "OK":
            raise RuntimeError("无法打开收件箱")
        status, data = mailbox.search(None, "UNSEEN")
        if status != "OK":
            raise RuntimeError("无法查询未读邮件")

        ids = data[0].split()
        items = []
        for message_id in reversed(ids[-5:]):
            status, parts = mailbox.fetch(
                message_id,
                "(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])",
            )
            if status != "OK" or not parts or not isinstance(parts[0], tuple):
                continue
            message = email.message_from_bytes(parts[0][1])
            date_text = decode(message.get("Date"))
            try:
                date_text = parsedate_to_datetime(date_text).astimezone().strftime("%m-%d %H:%M")
            except Exception:
                date_text = date_text[:16]
            items.append({
                "from": decode(message.get("From")),
                "subject": decode(message.get("Subject")),
                "date": date_text,
            })

        print(json.dumps({"unread": len(ids), "messages": items}, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except imaplib.IMAP4.error:
        print("登录失败，请检查邮箱地址、客户端协议和专用密码", file=sys.stderr)
        sys.exit(2)
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
