// SPDX-License-Identifier: GPL-2.0-only
// redux-osk-pointer: make an H700 handheld (RG34XX-SP first) usable with the fly-out OSK on a device with no touchscreen.
// It reads the analog stick (adc-joystick: ABS_X/ABS_Y) and the face buttons (gpio-keys-gamepad) and
// emits a relative pointer + left/right click through uinput, so libinput (under cage/wvkbd) sees a
// normal mouse. RetroArch reads the raw pads directly and is unaffected; this only runs inside a
// redux-kbapp (cage) session, which starts and stops it.
//
// Mapping: left stick -> cursor; A (BTN_SOUTH) -> left click; B (BTN_EAST) -> right click.
// DESK ONLY: stick range/centre and button codes follow the mainline DT; untested on hardware.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <dirent.h>
#include <poll.h>
#include <linux/input.h>
#include <linux/uinput.h>

#define DEAD 350          // deadzone around centre (range 0..4095, centre ~2048)
#define CENTRE 2048
#define MAXSTEP 12        // max pixels per tick at full deflection
#define TICK_MS 16

static int test_bit(const unsigned long *b, int n){ return (b[n/(8*sizeof(long))] >> (n%(8*sizeof(long)))) & 1; }

// Open the first /dev/input/event* whose EV_ABS has ABS_X (the stick) or EV_KEY has BTN_SOUTH (pad).
static int find_dev(int want_abs){
    DIR *d = opendir("/dev/input"); if(!d) return -1;
    struct dirent *e; int fd=-1;
    while((e=readdir(d))){
        if(strncmp(e->d_name,"event",5)) continue;
        char p[300]; snprintf(p,sizeof p,"/dev/input/%s",e->d_name);
        int f=open(p,O_RDONLY|O_NONBLOCK); if(f<0) continue;
        unsigned long ev[ (EV_MAX+8*sizeof(long))/(8*sizeof(long)) ]={0};
        unsigned long bits[ (KEY_MAX+8*sizeof(long))/(8*sizeof(long)) ]={0};
        ioctl(f,EVIOCGBIT(0,sizeof ev),ev);
        if(want_abs && test_bit(ev,EV_ABS)){
            ioctl(f,EVIOCGBIT(EV_ABS,sizeof bits),bits);
            if(test_bit(bits,ABS_X)){ fd=f; break; }
        } else if(!want_abs && test_bit(ev,EV_KEY)){
            ioctl(f,EVIOCGBIT(EV_KEY,sizeof bits),bits);
            if(test_bit(bits,BTN_SOUTH)){ fd=f; break; }
        }
        close(f);
    }
    closedir(d); return fd;
}

static int make_uinput(void){
    int fd=open("/dev/uinput",O_WRONLY|O_NONBLOCK); if(fd<0){ perror("/dev/uinput"); return -1; }
    ioctl(fd,UI_SET_EVBIT,EV_REL); ioctl(fd,UI_SET_RELBIT,REL_X); ioctl(fd,UI_SET_RELBIT,REL_Y);
    ioctl(fd,UI_SET_EVBIT,EV_KEY); ioctl(fd,UI_SET_KEYBIT,BTN_LEFT); ioctl(fd,UI_SET_KEYBIT,BTN_RIGHT);
    struct uinput_setup us; memset(&us,0,sizeof us);
    us.id.bustype=BUS_VIRTUAL; strcpy(us.name,"ReduxOS OSK pointer");
    if(ioctl(fd,UI_DEV_SETUP,&us)<0 || ioctl(fd,UI_DEV_CREATE)<0){ perror("uinput setup"); close(fd); return -1; }
    return fd;
}

static void emit(int fd,int type,int code,int val){
    struct input_event ie; memset(&ie,0,sizeof ie); ie.type=type; ie.code=code; ie.value=val;
    if(write(fd,&ie,sizeof ie)<0){}
}
static void sync_ev(int fd){ emit(fd,EV_SYN,SYN_REPORT,0); }

static int accel(int axis){
    int d = axis - CENTRE;
    if(d>-DEAD && d<DEAD) return 0;
    double f=(double)(d>0?d-DEAD:d+DEAD)/(double)(2048-DEAD); // -1..1
    int s=(int)(f*MAXSTEP);
    return s;
}

int main(void){
    int stick=find_dev(1), pad=find_dev(0), ui=make_uinput();
    if(ui<0) return 1;
    if(stick<0 && pad<0){ fprintf(stderr,"redux-osk-pointer: no stick or pad found\n"); return 1; }
    int ax=CENTRE, ay=CENTRE;
    struct pollfd pfd[2]; int n=0;
    int si=-1, pi=-1;
    if(stick>=0){ pfd[n].fd=stick; pfd[n].events=POLLIN; si=n; n++; }
    if(pad>=0){ pfd[n].fd=pad; pfd[n].events=POLLIN; pi=n; n++; }
    for(;;){
        int r=poll(pfd,n,TICK_MS);
        if(r>0){
            struct input_event ie;
            if(si>=0 && (pfd[si].revents&POLLIN))
                while(read(stick,&ie,sizeof ie)==(int)sizeof ie){
                    if(ie.type==EV_ABS){ if(ie.code==ABS_X) ax=ie.value; else if(ie.code==ABS_Y) ay=ie.value; }
                }
            if(pi>=0 && (pfd[pi].revents&POLLIN))
                while(read(pad,&ie,sizeof ie)==(int)sizeof ie){
                    if(ie.type==EV_KEY && ie.value<2){
                        if(ie.code==BTN_SOUTH) emit(ui,EV_KEY,BTN_LEFT,ie.value);
                        else if(ie.code==BTN_EAST) emit(ui,EV_KEY,BTN_RIGHT,ie.value);
                        sync_ev(ui);
                    }
                }
        }
        int dx=accel(ax), dy=accel(ay);
        if(dx||dy){ if(dx) emit(ui,EV_REL,REL_X,dx); if(dy) emit(ui,EV_REL,REL_Y,dy); sync_ev(ui); }
    }
}
