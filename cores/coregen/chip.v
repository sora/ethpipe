
`timescale 1ns/ 10 ps

module chip(jcex); // dummy output jcex
output jcex;
   
   reg   [ 7:0] R0, R1, R2, R3;
   wire  [ 7:0] sciwdata, scirmxdata;
   wire  [17:0] sciaddr;
   
   assign scirmxdata = ((sciaddr == 18'h00000)?(8'h12):(8'h0)) |
                       ((sciaddr == 18'h00001)?(8'h34):(8'h0)) |
                       ((sciaddr == 18'h00002)?(8'h56):(8'h0)) |
                       ((sciaddr == 18'h00003)?(8'h78):(8'h0)) |
                       ((sciaddr == 18'h00004)?( R0  ):(8'h0)) |
                       ((sciaddr == 18'h00005)?( R1  ):(8'h0)) |
                       ((sciaddr == 18'h00006)?( R2  ):(8'h0)) |
                       ((sciaddr == 18'h00007)?( R3  ):(8'h0)) ;
   
   dummy_sym ORCAstra_inst
   (  .rstn       (1'b1      ),
      .scirmxdata (scirmxdata),
      .sciwdata   (sciwdata  ),
      .sciaddr    (sciaddr   ),
      .sciwstn    (sciwstn   ),
      .scird      (scird     ),
      .jcex       (jcex      )
   );
   
   always @(negedge sciwstn)
   begin
      if (jcex && (sciaddr == 18'h00004)) R0 <= sciwdata;
      if (jcex && (sciaddr == 18'h00005)) R1 <= sciwdata;
      if (jcex && (sciaddr == 18'h00006)) R2 <= sciwdata;
      if (jcex && (sciaddr == 18'h00007)) R3 <= sciwdata;
   end
   
endmodule
