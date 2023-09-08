`timescale 1ns/10ps
module ISE( clk, reset, image_in_index, pixel_in, busy, out_valid, color_index, image_out_index);
input clk;
input reset;
input [4:0] image_in_index;
input [23:0] pixel_in;
output reg busy;
output reg out_valid;
output reg [1:0] color_index;
output reg [4:0] image_out_index;

reg [23:0] R_strength, G_strength, B_strength;
reg [14:0] R_pixel, G_pixel, B_pixel;
reg [5:0] R_index [0:31], G_index [0:31], B_index [0:31];
reg [27:0] R_score [0:31], G_score [0:31], B_score [0:31];
reg [27:0]min;
reg [4:0]min_site;

reg [5:0] counter32;
reg [14:0] counter16384;
reg CAL_done, IN_done;
reg [4:0] counter_r, counter_g, counter_b;
reg [4:0]counter_r_out, counter_g_out, counter_b_out;
reg OUT_CAL_DONE;
reg [2:0] cs, ns;
parameter IDLE = 3'd0, IN = 3'd1, CAL_PIX = 3'd2,CAL_ORDER =3'd3, OUT_CAL = 3'd4,OUT=3'd5;

wire [7:0] r, g, b;
wire finish_r,finish_g,finish_b;
assign r = pixel_in[23:16];
assign g = pixel_in[15:8];
assign b = pixel_in[7:0];

integer i,i1,i2,j1,j2;
reg [5:0] counter_outcal;

//decide rgb picture
reg [2:0]rgb;
always @(*) begin
    if(cs==CAL_PIX | cs==CAL_ORDER)begin
        if(R_pixel > G_pixel && R_pixel> B_pixel)
            rgb=3'b100;
        else if(G_pixel> B_pixel && G_pixel > R_pixel)
            rgb=3'b010;
        else if(B_pixel > R_pixel && B_pixel > G_pixel)
            rgb=3'b001;
        else
            rgb=3'b000;
    end
    else
         rgb = 0;
end

//=========================================
reg [27:0] rstdiv, gstdiv, bstdiv;
wire [27:0]colordiv;
reg [14:0]color_pixel;
reg [23:0]color_strength;

always @(*) begin
    case(rgb)
        3'b100:color_pixel=R_pixel;
        3'b010:color_pixel=G_pixel;
        3'b001:color_pixel=B_pixel;
        default:color_pixel=0;
    endcase
end

always @(*) begin
    case(rgb)
        3'b100:color_strength=R_strength;
        3'b010:color_strength=G_strength;
        3'b001:color_strength=B_strength;
        default:color_strength=0;
    endcase
end

always @(*) begin
    if(rgb==3'b100)
        rstdiv=colordiv;
    else
        rstdiv=0;
end

always @(*) begin
    if(rgb==3'b010)
        gstdiv=colordiv;
    else
        gstdiv=0;
end

always @(*) begin
    if(rgb==3'b001)
        bstdiv=colordiv;
    else
        bstdiv=0;
end

assign  colordiv = (color_strength << 5)/color_pixel;
assign finish_r=(counter_r==counter_r_out)?1:0;
assign finish_g=(counter_g==counter_g_out)?1:0;
assign finish_b=(counter_b==counter_b_out)?1:0;

//===========================================
//strength to score
always @(posedge clk ) begin//or posedge reset
    if(reset)
        for(j2=0;j2<32;j2=j2+1)begin
            R_score[j2] <= 28'b1111111111111111111111111111;
            G_score[j2] <= 28'b1111111111111111111111111111;
            B_score[j2] <= 28'b1111111111111111111111111111;
        end
    else if(cs==CAL_PIX)begin
        case(rgb)
            3'b100:
                R_score[counter_r] <= rstdiv;//counter32-1
            3'b010:
                G_score[counter_g] <= gstdiv;
            3'b001:
                B_score[counter_b] <= bstdiv;
        endcase
    end
    else if(cs==OUT)begin
        if(~finish_r)
            R_score[min_site] <= 28'b1111111111111111111111111111;
        else if(~finish_g)
            G_score[min_site] <= 28'b1111111111111111111111111111;
        else if(~finish_b)
            B_score[min_site] <= 28'b1111111111111111111111111111;
    end
end

//CAL_done
always @(posedge clk ) begin
    if(reset)
        CAL_done <=0;
    else if(cs==CAL_ORDER)
        CAL_done <=1;
    else
        CAL_done <=0;
end

always @(posedge clk ) begin
    if(reset)
        cs <= IDLE;
    else
        cs <= ns;
end

always @(*) begin
    case (cs)
        IDLE:begin
            ns = IN;
        end
        IN:begin
            if(counter16384 == 16384)
                ns = CAL_PIX;
            else 
                ns = IN;
            end
        CAL_PIX:begin
                ns = CAL_ORDER;
            end
        CAL_ORDER:begin
            if(CAL_done & IN_done)
                ns = OUT_CAL;
            else if(CAL_done)
                ns = IN;
            else    
                ns = CAL_ORDER;
        end
        OUT_CAL:begin
            ns = (OUT_CAL_DONE)?OUT:OUT_CAL;
        end
        OUT:begin
            ns=OUT_CAL;
        end
        default:
            ns=IDLE;
    endcase
end

//OUT_CAL_DONE
always @(*) begin
    if (cs==OUT_CAL) begin
        if(~finish_r)begin//& counter_r==counter_outcal
            if( counter_r==counter_outcal)
                 OUT_CAL_DONE=1;
            else 
                OUT_CAL_DONE=0;
        end
        else begin 
        if(~finish_g)begin  
            if(counter_g==counter_outcal)
                OUT_CAL_DONE=1;
            else 
                OUT_CAL_DONE=0;
        end
        else if(~finish_b & counter_b==counter_outcal)
            OUT_CAL_DONE=1;
        else
            OUT_CAL_DONE=0;
        end
    end
    else
        OUT_CAL_DONE=0;
end

always @(posedge clk ) begin
    if(reset)
        R_pixel <= 0;
    else if(cs == IN & counter16384 < 16384)begin
        if(r >= g & r >= b)
            R_pixel <= R_pixel + 1;
        //else 
        //    R_pixel <= R_pixel;
    end
    else if(CAL_done)
        R_pixel <= 0;
end

always @(posedge clk ) begin
    if(reset)
        G_pixel <= 0;
    else if(cs == IN && counter16384 < 16384)begin
        if(g >= b && g > r)
            G_pixel <= G_pixel + 1;
        else 
            G_pixel <= G_pixel;
    end
    else if(CAL_done)
        G_pixel <= 0;
end

always @(posedge clk ) begin
    if(reset)
        B_pixel <= 0;
    else if(cs == IN && counter16384 < 16384)begin
        if(b > r && b > g)
            B_pixel <= B_pixel + 1;
        else 
            B_pixel <= B_pixel;
    end
    else if(CAL_done)
        B_pixel <= 0;
end

always @(posedge clk ) begin
    if(reset)
        R_strength <= 0;
    else if(cs == IN && counter16384 < 16384)
        if(r >= g && r >= b)
            R_strength <= R_strength + r;
        else
            R_strength <= R_strength;
    else if(cs == CAL_ORDER)
        if(CAL_done)
            R_strength <= 0;
        else 
            R_strength <= R_strength;
end

always @(posedge clk ) begin
    if(reset)
        G_strength <= 0;
    else if(cs == IN && counter16384 < 16384)
        if(g >= b && g > r)
            G_strength <= G_strength + g;
        else 
            G_strength <= G_strength;
    else if(cs == CAL_ORDER)
        if(CAL_done)
            G_strength <= 0;
        else 
            G_strength <= G_strength;
end

always @(posedge clk ) begin
    if(reset)
        B_strength <= 0;
    else if(cs == IN && counter16384 < 16384)
        if(b > r && b > g)
            B_strength <= B_strength + b;
        else
            B_strength <= B_strength;
    else if(cs == CAL_ORDER)
        if(CAL_done)
            B_strength <= 0;
        else 
            B_strength <= B_strength;
end

always @(posedge clk ) begin
    if(reset)
        counter16384 <= 0;
    else if(cs == IN)
        counter16384 <= counter16384 + 1;
    else 
        counter16384 <= 0;
end

always @(posedge clk ) begin
    if(reset)
        IN_done <= 0;
    else if(cs == CAL_ORDER && counter32 == 32)
        IN_done <= 1;
end

always @(posedge clk ) begin
    if(reset)
        counter32 <= 0;
    else if(cs == IN)
        if(counter16384 == 16384)
            counter32 <= counter32 + 1;
        else 
            counter32 <= counter32;
    else
        counter32 <= counter32;
end

always @(*) begin
    if(cs == IDLE)
        busy = 0;
    else if(cs == IN)
        if(counter16384 == 16384)
            busy = 1;
        else 
            busy = 0;
    else
        busy = 1;
end

always @(posedge clk ) begin
    if(reset)
        out_valid <= 0;
    else if(cs == OUT)
        out_valid <= 1;
    else 
        out_valid <= 0;
end

always @(posedge clk ) begin
    if(reset)
        color_index <= 2'b00;
    else if(cs == OUT)
        if(~finish_r)
            color_index <= 2'b00;
        else if(~finish_g)
            color_index <= 2'b01;
        else if(~finish_b)
            color_index <= 2'b10;
    else 
        color_index <= 2'b00;
end

//counter_r,g,b
always @(posedge clk ) begin
    if(reset)begin
        counter_r<=0;
        counter_g<=0;
        counter_b<=0;
    end
    else if (cs==CAL_PIX) begin
        case(rgb)
            3'b100:counter_r<=counter_r+1;
            3'b010:counter_g<=counter_g+1;
            3'b001:counter_b<=counter_b+1;
        endcase
    end
end

//counter_r,g,b_out
always @(posedge clk ) begin
    if(reset)begin
        counter_r_out<=0;
        counter_g_out<=0;
        counter_b_out<=0;
    end
    else if(cs == OUT)
        if(~finish_r)
            counter_r_out <= counter_r_out + 1;
        else if(~finish_g)
            counter_g_out <= counter_g_out + 1;
        else if(~finish_b)
            counter_b_out <= counter_b_out + 1;
end

always @(posedge clk ) begin
    if(reset)
        image_out_index <= 0;
    else if(cs == OUT)
        if(~finish_r)
            image_out_index <= R_index[min_site];
        else if(~finish_g)  
            image_out_index <= G_index[min_site];
        else if(~finish_b)
            image_out_index <= B_index[min_site];
end

//counter_outcal 
always @(posedge clk ) begin
    if(reset)
        counter_outcal<=0;
    else if(cs==OUT_CAL)
        counter_outcal<=counter_outcal+1;
    else
        counter_outcal<=0;
end

//min output,min_site
always @(posedge clk ) begin
    if(reset)
        min <= 28'b1111111111111111111111111111;
    else if(cs ==OUT_CAL)begin
        if(~finish_r)begin
            if (R_score[counter_outcal]<min) begin
                min<=R_score[counter_outcal];
                min_site<=counter_outcal;
            end
        end
        else if(~finish_g)begin
            if (G_score[counter_outcal]<min) begin
                min<=G_score[counter_outcal];
                min_site<=counter_outcal;
            end
        end
        else if(~finish_b)begin
            if (B_score[counter_outcal]<min) begin
                min<=B_score[counter_outcal];
                min_site<=counter_outcal;
            end
        end
    end
    else
        min <= 28'b1111111111111111111111111111;
end

//index
always @(posedge clk ) begin
    if(reset)begin
        for(j1=0;j1<32;j1=j1+1)begin
            R_index[j1] <= 6'd31;
            G_index[j1] <= 6'd31;
            B_index[j1] <= 6'd31;
        end
    end
    else if(cs==CAL_ORDER & ~CAL_done)begin
        case(rgb)
            3'b100:R_index[counter_r-1] <=counter32-1;//
            3'b010:G_index[counter_g-1] <=counter32-1;
            3'b001:B_index[counter_b-1] <=counter32-1;
        endcase
    end
end
endmodule
