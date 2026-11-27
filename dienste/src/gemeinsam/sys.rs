//! Dünne Schicht über die Linux-Systemaufrufe, die die Standardbibliothek nicht anbietet
//! (inotify, fanotify, poll, Signale, Absender eines Sockets).
use std::ffi::{c_void, CString};
use std::os::raw::{c_char, c_int, c_uint};
use std::sync::atomic::{AtomicBool, Ordering};

extern "C" {
    pub fn inotify_init1(flags: c_int) -> c_int;
    pub fn inotify_add_watch(fd: c_int, pfad: *const c_char, maske: u32) -> c_int;
    pub fn fanotify_init(flags: c_uint, event_f_flags: c_uint) -> c_int;
    pub fn fanotify_mark(fd: c_int, flags: c_uint, maske: u64, dirfd: c_int, pfad: *const c_char) -> c_int;
    pub fn read(fd: c_int, buf: *mut c_void, n: usize) -> isize;
    pub fn write(fd: c_int, buf: *const c_void, n: usize) -> isize;
    pub fn close(fd: c_int) -> c_int;
    pub fn poll(fds: *mut PollFd, n: u64, timeout: c_int) -> c_int;
    pub fn kill(pid: c_int, sig: c_int) -> c_int;
    pub fn signal(sig: c_int, handler: extern "C" fn(c_int)) -> usize;
    pub fn getsockopt(fd: c_int, level: c_int, name: c_int, wert: *mut c_void, laenge: *mut u32) -> c_int;
    pub fn geteuid() -> c_uint;
}

#[repr(C)]
pub struct PollFd {
    pub fd: c_int,
    pub events: i16,
    pub revents: i16,
}

pub const POLLIN: i16 = 0x1;
pub const POLLPRI: i16 = 0x2;
pub const POLLERR: i16 = 0x8;

// inotify
pub const IN_NONBLOCK: c_int = 0o4000;
pub const IN_CLOEXEC: c_int = 0o2000000;
pub const IN_ATTRIB: u32 = 0x4;
pub const IN_CLOSE_WRITE: u32 = 0x8;
pub const IN_MOVED_FROM: u32 = 0x40;
pub const IN_MOVED_TO: u32 = 0x80;
pub const IN_CREATE: u32 = 0x100;
pub const IN_DELETE: u32 = 0x200;
pub const IN_ONLYDIR: u32 = 0x0100_0000;
pub const IN_ISDIR: u32 = 0x4000_0000;

// fanotify
pub const FAN_CLOEXEC: c_uint = 0x1;
pub const FAN_NONBLOCK: c_uint = 0x2;
pub const FAN_CLASS_NOTIF: c_uint = 0x0;
pub const FAN_CLASS_CONTENT: c_uint = 0x4;
pub const FAN_MARK_ADD: c_uint = 0x1;
pub const FAN_MARK_MOUNT: c_uint = 0x10;
pub const FAN_MARK_FILESYSTEM: c_uint = 0x100;
pub const FAN_CLOSE_WRITE: u64 = 0x8;
pub const FAN_OPEN_EXEC_PERM: u64 = 0x0004_0000;
pub const FAN_ALLOW: u32 = 0x1;
pub const FAN_DENY: u32 = 0x2;
pub const O_LARGEFILE: c_uint = 0o100000;
pub const O_CLOEXEC: c_uint = 0o2000000;
pub const AT_FDCWD: c_int = -100;

pub const SIGKILL: c_int = 9;
pub const SIGCONT: c_int = 18;
pub const SIGSTOP: c_int = 19;

/// Kopf eines fanotify-Ereignisses (struct fanotify_event_metadata, 24 Byte)
#[repr(C)]
#[derive(Clone, Copy)]
pub struct FanMeta {
    pub event_len: u32,
    pub vers: u8,
    pub reserved: u8,
    pub metadata_len: u16,
    pub mask: u64,
    pub fd: i32,
    pub pid: i32,
}
pub const FAN_META: usize = std::mem::size_of::<FanMeta>();

#[repr(C)]
pub struct FanAntwort {
    pub fd: i32,
    pub response: u32,
}

/// Kopf eines inotify-Ereignisses (Name folgt dahinter)
#[repr(C)]
#[derive(Clone, Copy)]
pub struct InMeta {
    pub wd: i32,
    pub mask: u32,
    pub cookie: u32,
    pub len: u32,
}
pub const IN_META: usize = std::mem::size_of::<InMeta>();

/// inotify-Puffer zerlegen: (wd, maske, name)
pub fn inotify_lesen(fd: c_int) -> Vec<(i32, u32, String)> {
    let mut aus = Vec::new();
    let mut buf = vec![0u8; 8192];
    loop {
        let n = unsafe { read(fd, buf.as_mut_ptr() as *mut c_void, buf.len()) };
        if n <= 0 {
            break;
        }
        let n = n as usize;
        let mut off = 0;
        while off + IN_META <= n {
            let m: InMeta = unsafe { std::ptr::read_unaligned(buf.as_ptr().add(off) as *const InMeta) };
            let ende = (off + IN_META + m.len as usize).min(n);
            let roh = &buf[off + IN_META..ende];
            let name = String::from_utf8_lossy(roh.split(|&b| b == 0).next().unwrap_or(&[])).into_owned();
            aus.push((m.wd, m.mask, name));
            off = ende;
        }
    }
    aus
}

pub fn beobachten(fd: c_int, pfad: &str, maske: u32) -> i32 {
    let c = c(pfad);
    unsafe { inotify_add_watch(fd, c.as_ptr(), maske) }
}

static ENDE: AtomicBool = AtomicBool::new(false);
extern "C" fn beim_signal(_: c_int) {
    ENDE.store(true, Ordering::SeqCst);
}
/// SIGTERM/SIGINT/SIGHUP → ende() wird true (die Hauptschleife räumt dann auf)
pub fn signale_abfangen() {
    unsafe {
        signal(15, beim_signal);
        signal(2, beim_signal);
        signal(1, beim_signal);
    }
}
pub fn ende() -> bool {
    ENDE.load(Ordering::SeqCst)
}

pub fn c(s: &str) -> CString {
    CString::new(s.replace('\0', "")).unwrap_or_default()
}

pub fn warte(fds: &mut [PollFd], ms: i32) -> i32 {
    unsafe { poll(fds.as_mut_ptr(), fds.len() as u64, ms) }
}

pub fn fd_pfad(fd: c_int) -> Option<String> {
    std::fs::read_link(format!("/proc/self/fd/{}", fd)).ok().map(|p| p.to_string_lossy().into_owned())
}

pub fn uid_von(pid: i32) -> Option<u32> {
    let s = std::fs::read_to_string(format!("/proc/{}/status", pid)).ok()?;
    s.lines().find(|z| z.starts_with("Uid:"))?.split_whitespace().nth(1)?.parse().ok()
}

pub fn name_von(pid: i32) -> String {
    std::fs::read_to_string(format!("/proc/{}/comm", pid)).map(|s| s.trim().to_string()).unwrap_or_default()
}

pub fn programm_von(pid: i32) -> Option<String> {
    std::fs::read_link(format!("/proc/{}/exe", pid)).ok().map(|p| p.to_string_lossy().into_owned())
}

/// Elternprozess (Feld 4 in /proc/pid/stat, hinter dem Namen in Klammern)
pub fn eltern_von(pid: i32) -> Option<i32> {
    let s = std::fs::read_to_string(format!("/proc/{}/stat", pid)).ok()?;
    let rest = &s[s.rfind(')')? + 2..];
    rest.split_whitespace().nth(1)?.parse().ok()
}

/// alle laufenden Prozess-Nummern
pub fn prozesse() -> Vec<i32> {
    std::fs::read_dir("/proc")
        .map(|d| d.filter_map(|e| e.ok()?.file_name().to_str()?.parse().ok()).collect())
        .unwrap_or_default()
}

#[repr(C)]
struct Ucred {
    pid: i32,
    uid: u32,
    gid: u32,
}

/// Wer ist am anderen Ende des Sockets? (pid, uid) – vom Kern geliefert, nicht fälschbar
pub fn gegenueber(fd: c_int) -> Option<(i32, u32)> {
    let mut u = Ucred { pid: 0, uid: u32::MAX, gid: 0 };
    let mut l = std::mem::size_of::<Ucred>() as u32;
    let r = unsafe { getsockopt(fd, 1, 17, &mut u as *mut Ucred as *mut c_void, &mut l) };
    if r == 0 {
        Some((u.pid, u.uid))
    } else {
        None
    }
}

pub fn fehlernummer() -> i32 {
    std::io::Error::last_os_error().raw_os_error().unwrap_or(0)
}

pub struct Benutzer {
    pub uid: u32,
    pub gid: u32,
    pub name: String,
    pub heim: String,
}

/// normale Benutzer (uid 1000–59999) aus /etc/passwd
pub fn benutzer() -> Vec<Benutzer> {
    let t = std::fs::read_to_string("/etc/passwd").unwrap_or_default();
    t.lines()
        .filter_map(|z| {
            let f: Vec<&str> = z.split(':').collect();
            if f.len() < 7 {
                return None;
            }
            let uid: u32 = f[2].parse().ok()?;
            if !(1000..60000).contains(&uid) {
                return None;
            }
            Some(Benutzer { uid, gid: f[3].parse().ok()?, name: f[0].to_string(), heim: f[5].to_string() })
        })
        .collect()
}

pub fn gid_von(uid: u32) -> u32 {
    benutzer().into_iter().find(|b| b.uid == uid).map(|b| b.gid).unwrap_or(uid)
}
