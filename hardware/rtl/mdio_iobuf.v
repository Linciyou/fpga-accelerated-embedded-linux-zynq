module mdio_iobuf (
    input  wire mdio_o,
    input  wire mdio_t,
    output wire mdio_i,
    inout  wire mdio_io
);

    IOBUF mdio_buffer (
        .I(mdio_o),
        .T(mdio_t),
        .O(mdio_i),
        .IO(mdio_io)
    );

endmodule
