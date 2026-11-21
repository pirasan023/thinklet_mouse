package ai.thinklet.handmouse;
import android.app.Activity;
import android.os.Bundle;
import android.Manifest;
import android.content.pm.PackageManager;
import android.graphics.*;
import android.hardware.Camera;
import android.view.*;
import android.widget.TextView;
import java.io.*;
import java.net.*;

/** USB-only JPEG bridge; no audio, recording, or network-facing listener. */
@SuppressWarnings("deprecation")
public class MainActivity extends Activity implements SurfaceHolder.Callback {
    private Camera camera;
    private SurfaceView surface;
    private static final class Frame {
        final byte[] jpeg;
        final long time;
        Frame(byte[] jpeg, long time) { this.jpeg=jpeg;this.time=time; }
    }
    private volatile Frame latest;
    private volatile ServerSocket server;
    private volatile boolean running;
    private long lastFrame;
    private TextView status;
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        surface = new SurfaceView(this);
        setContentView(surface);
        status = new TextView(this);
        status.setTextColor(Color.WHITE); status.setBackgroundColor(0x99000000);
        status.setText("THINKLET Hand Mouse — USB camera bridge");
        addContentView(status, new ViewGroup.LayoutParams(-1, 60));
        surface.getHolder().addCallback(this);
        if (checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED)
            requestPermissions(new String[]{Manifest.permission.CAMERA}, 1);
    }
    @Override public void onRequestPermissionsResult(int r, String[] p, int[] g) {
        super.onRequestPermissionsResult(r,p,g);
        if (g.length>0 && g[0]==PackageManager.PERMISSION_GRANTED && surface.getHolder().getSurface().isValid()) startCamera();
    }
    @Override public void surfaceCreated(SurfaceHolder h) { startCamera(); }
    @Override public void surfaceChanged(SurfaceHolder h,int f,int w,int height) {}
    @Override public void surfaceDestroyed(SurfaceHolder h) { stopCamera(); }
    private void startCamera() {
        if(camera!=null || checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED) return;
        try {
            camera=Camera.open(0);
            Camera.Parameters p=camera.getParameters();
            Camera.Size best=p.getSupportedPreviewSizes().get(0);
            for(Camera.Size s:p.getSupportedPreviewSizes())
                if(Math.abs(s.width-960)+Math.abs(s.height-720)<Math.abs(best.width-960)+Math.abs(best.height-720)) best=s;
            final int w=best.width, h=best.height;
            p.setPreviewSize(w,h); p.setPreviewFormat(ImageFormat.NV21);
            if(p.getSupportedFocusModes().contains(Camera.Parameters.FOCUS_MODE_CONTINUOUS_VIDEO)) p.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_VIDEO);
            camera.setParameters(p); camera.setPreviewDisplay(surface.getHolder());
            camera.setPreviewCallbackWithBuffer((data,c)->{
                try {
                    long now=android.os.SystemClock.elapsedRealtime();
                    if(now-lastFrame>=66) {
                        lastFrame=now;
                        ByteArrayOutputStream out=new ByteArrayOutputStream();
                        new YuvImage(data,ImageFormat.NV21,w,h,null).compressToJpeg(new Rect(0,0,w,h),85,out);
                        latest=new Frame(out.toByteArray(),now);
                    }
                } finally { if(camera!=null) c.addCallbackBuffer(data); }
            });
            for(int i=0;i<3;i++) camera.addCallbackBuffer(new byte[w*h*3/2]);
            camera.startPreview(); running=true;
            new Thread(this::serve,"usb-jpeg").start();
            status.setText("USB camera ready • "+w+"×"+h+" • localhost:8765");
        } catch(Exception e) { status.setText("Camera error: "+e); stopCamera(); }
    }
    private void serve() {
        try(ServerSocket listener=new ServerSocket()) {
            listener.setReuseAddress(true);
            listener.bind(new InetSocketAddress(InetAddress.getByName("127.0.0.1"),8765));
            server=listener;
            while(running) {
                try(Socket s=listener.accept()) {
                    s.setSoTimeout(1000);
                    BufferedReader in=new BufferedReader(new InputStreamReader(s.getInputStream()));
                    String request=in.readLine();
                    String line; while((line=in.readLine())!=null && !line.isEmpty()) {}
                    Frame frame=latest;
                    boolean ok=request!=null && request.startsWith("GET /frame ") && frame!=null && android.os.SystemClock.elapsedRealtime()-frame.time<500;
                    byte[] body=ok?frame.jpeg:"Camera not ready".getBytes("UTF-8");
                    OutputStream out=s.getOutputStream();
                    out.write(("HTTP/1.1 "+(ok?"200 OK":"503 Unavailable")+"\r\nContent-Type: "+(ok?"image/jpeg":"text/plain")+"\r\nX-Frame-Id: "+(frame==null?0:frame.time)+"\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: "+body.length+"\r\n\r\n").getBytes("US-ASCII"));
                    out.write(body); out.flush();
                } catch(IOException e) { if(!running) break; }
            }
        } catch(IOException e) { runOnUiThread(()->status.setText("USB bridge error: "+e)); }
    }
    private void stopCamera() {
        running=false; latest=null;
        try { if(server!=null) server.close(); } catch(IOException ignored) {}
        if(camera!=null) { camera.setPreviewCallbackWithBuffer(null); camera.stopPreview(); camera.release(); camera=null; }
    }
    @Override protected void onDestroy(){ stopCamera(); super.onDestroy(); }
}
