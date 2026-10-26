import struct,sys,hashlib
def read(path):
    d=open(path,'rb').read()
    magic,fmt,maj,mnr,pat,flags=struct.unpack_from('<4sIIIII',d,0)
    assert magic==b'GDPC',magic
    file_base,dir_off=struct.unpack_from('<QQ',d,24)
    hdr=dict(fmt=fmt,ver=(maj,mnr,pat),flags=flags,file_base=file_base,dir_off=dir_off)
    p=dir_off; n,=struct.unpack_from('<I',d,p); p+=4
    files=[]
    for _ in range(n):
        l,=struct.unpack_from('<I',d,p); p+=4
        name=d[p:p+l].rstrip(b'\0').decode(); p+=l
        off,size=struct.unpack_from('<QQ',d,p); p+=16
        md5=d[p:p+16]; p+=16
        fl,=struct.unpack_from('<I',d,p); p+=4
        files.append((name,off,size,md5,fl))
    return d,hdr,files
def write(path,d,hdr,files,keep):
    out=bytearray()
    out+=struct.pack('<4sIIIII',b'GDPC',hdr['fmt'],*hdr['ver'],hdr['flags'])
    out+=struct.pack('<QQ',0,0)+b'\0'*64   # file_base, dir_offset patched below
    entries=[]
    for name,off,size,md5,fl in files:
        if not keep(name): continue
        while len(out)%32: out+=b'\0'
        start=len(out)
        data=d[hdr['file_base']+off:hdr['file_base']+off+size]
        assert hashlib.md5(data).digest()==md5, name
        out+=data
        entries.append((name,start,size,md5,fl))
    while len(out)%32: out+=b'\0'
    dir_off=len(out)
    out+=struct.pack('<I',len(entries))
    for name,start,size,md5,fl in entries:
        b=name.encode()+b'\0'
        while len(b)%4: b+=b'\0'
        out+=struct.pack('<I',len(b))+b+struct.pack('<QQ',start,size)+md5+struct.pack('<I',fl)
    struct.pack_into('<Q',out,32,dir_off)   # dir_offset at byte 32
    open(path,'wb').write(out)
    return [e[0] for e in entries]
if __name__=='__main__':
    d,hdr,files=read(sys.argv[1]); print(hdr)
    for f in files: print(f[0],f[2],f[4])
